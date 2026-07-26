#if os(iOS)
@preconcurrency import ExternalAccessory
import Foundation

/// iOS ExternalAccessoryセッションをELM/STN連続バイトストリームとして公開します。
actor IOSExternalAccessoryOBDTransport: OBDCommandTransport {
    /// 接続対象の非可逆ExternalAccessory識別子です。
    private let endpoint: OBDConnectionEndpoint
    /// メーカー確認済みExternalAccessoryプロトコル許可集合です。
    private let configuration: IOSExternalAccessoryProtocolConfiguration
    /// ExternalAccessoryを非可逆識別子へ変換します。
    private let mapper = IOSExternalAccessorySnapshotMapper()
    /// 現在開いているExternalAccessoryセッションです。
    private var session: EASession?
    /// 現在開いているアクセサリー入力ストリームです。
    private var inputStream: InputStream?
    /// 現在開いているアクセサリー出力ストリームです。
    private var outputStream: OutputStream?
    /// 次のELMプロンプト境界まで保持する未返却受信バイトです。
    private var readBuffer = Data()

    /// Bluetooth Classic終端とメーカー確認済みプロトコルを固定して生成します。
    ///
    /// 責務: 1件の選択済みBluetooth Classic終端をExternalAccessory通信条件へ結び付けます。
    /// - Parameters:
    ///   - endpoint: 選択済みExternalAccessoryの非可逆識別子を持つ終端。
    ///   - configuration: メーカー確認済みプロトコル許可集合。
    /// - Throws: Bluetooth Classic以外または空の許可集合では `VehicleIdentificationError.transportUnsupported`。
    init(
        endpoint: OBDConnectionEndpoint,
        configuration: IOSExternalAccessoryProtocolConfiguration
    ) throws {
        guard endpoint.transport == .bluetoothClassic,
              !configuration.protocolStrings.isEmpty else {
            throw VehicleIdentificationError.transportUnsupported
        }
        self.endpoint = endpoint
        self.configuration = configuration
    }

    /// 選択済みアクセサリーを再特定してExternalAccessoryストリームを開きます。
    ///
    /// 責務: 1件の接続済みアクセサリーと許可プロトコルから読書き可能なEASessionを確立します。
    /// - Throws: 対象不在、プロトコル不一致、セッション生成失敗、または期限内に開けない場合の通信エラー。
    func open() async throws {
        guard session == nil else { return }
        guard let match = matchingAccessory() else {
            throw VehicleIdentificationError.connectionFailed
        }
        guard let openedSession = EASession(
            accessory: match.accessory,
            forProtocol: match.protocolString
        ) else {
            throw VehicleIdentificationError.connectionFailed
        }
        session = openedSession
        inputStream = openedSession.inputStream
        outputStream = openedSession.outputStream
        readBuffer.removeAll(keepingCapacity: true)
        inputStream?.open()
        outputStream?.open()
        do {
            try await waitForStreamsToOpen()
        } catch {
            closeStreams()
            throw error
        }
    }

    /// 復帰文字を含むELM/STNコマンドを全バイト書き込みます。
    ///
    /// 責務: 1件の完全なコマンドバイト列を期限内にExternalAccessory出力へ送信します。
    /// - Parameter data: 復帰文字を含む完全なASCIIコマンド。
    /// - Throws: 未接続、ストリーム失敗、切断、または期限切れの場合の通信エラー。
    func write(_ data: Data) async throws {
        guard let outputStream else {
            throw VehicleIdentificationError.connectionFailed
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var writtenByteCount = 0
        while writtenByteCount < data.count {
            try Task.checkCancellation()
            try validate(outputStream)
            guard ContinuousClock.now < deadline else {
                throw VehicleIdentificationError.responseTimedOut
            }
            guard outputStream.hasSpaceAvailable else {
                try await Task.sleep(for: .milliseconds(10))
                continue
            }
            let count = data.withUnsafeBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return outputStream.write(
                    baseAddress.advanced(by: writtenByteCount),
                    maxLength: data.count - writtenByteCount
                )
            }
            guard count >= 0 else {
                throw VehicleIdentificationError.connectionFailed
            }
            if count == 0 {
                try await Task.sleep(for: .milliseconds(10))
            } else {
                writtenByteCount += count
            }
        }
    }

    /// ELM/STNの次の `>` プロンプトまでを読み取ります。
    ///
    /// 責務: ExternalAccessory入力を1件のELM/STNプロンプト境界まで期限付きで蓄積します。
    /// - Returns: `>` プロンプトを含む加工前応答バイト。
    /// - Throws: 未接続、ストリーム失敗、切断、または期限切れの場合の通信エラー。
    func readUntilPrompt() async throws -> Data {
        if let response = extractPromptResponse() {
            return response
        }
        guard let inputStream else {
            throw VehicleIdentificationError.connectionFailed
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var bytes = [UInt8](repeating: 0, count: 1_024)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try validate(inputStream)
            guard inputStream.hasBytesAvailable else {
                try await Task.sleep(for: .milliseconds(10))
                continue
            }
            let count = inputStream.read(&bytes, maxLength: bytes.count)
            guard count >= 0 else {
                throw VehicleIdentificationError.connectionFailed
            }
            if count > 0 {
                readBuffer.append(contentsOf: bytes.prefix(count))
                if let response = extractPromptResponse() {
                    return response
                }
            } else {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        throw VehicleIdentificationError.responseTimedOut
    }

    /// 現在のExternalAccessoryセッションとストリームを閉じます。
    ///
    /// 責務: 1件のExternalAccessory通信に属する全資源と未返却バイトを破棄します。
    func close() async {
        closeStreams()
    }

    /// 現在接続一覧から選択済み識別子と許可プロトコルに一致するアクセサリーを探します。
    ///
    /// 責務: 現在のExternalAccessory一覧を1件の接続対象と通信プロトコルへ解決します。
    /// - Returns: 再特定したアクセサリーと一致プロトコル。見つからない場合は `nil`。
    private func matchingAccessory() -> (accessory: EAAccessory, protocolString: String)? {
        for accessory in EAAccessoryManager.shared().connectedAccessories where accessory.isConnected {
            let snapshot = IOSExternalAccessorySnapshot(
                connectionID: accessory.connectionID,
                name: accessory.name,
                manufacturer: accessory.manufacturer,
                modelNumber: accessory.modelNumber,
                serialNumber: accessory.serialNumber,
                protocolStrings: accessory.protocolStrings,
                isConnected: accessory.isConnected
            )
            guard mapper.systemIdentifier(for: snapshot) == endpoint.systemIdentifier,
                  let protocolString = configuration.matchingProtocol(in: accessory.protocolStrings) else {
                continue
            }
            return (accessory, protocolString)
        }
        return nil
    }

    /// 入出力ストリームが期限内に開いたことを確認します。
    ///
    /// 責務: 現在のExternalAccessory入出力を送受信可能状態まで期限付きで待機します。
    /// - Throws: セッション欠損、ストリーム失敗、切断、または期限切れの場合の通信エラー。
    private func waitForStreamsToOpen() async throws {
        guard let inputStream, let outputStream else {
            throw VehicleIdentificationError.connectionFailed
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            try validate(inputStream)
            try validate(outputStream)
            if isOpen(inputStream.streamStatus), isOpen(outputStream.streamStatus) {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw VehicleIdentificationError.responseTimedOut
    }

    /// ストリーム状態が送受信可能かを判定します。
    ///
    /// 責務: 1件のFoundationストリーム状態を開通済み真偽値へ変換します。
    /// - Parameter status: Foundationが報告したストリーム状態。
    /// - Returns: 開通中、読取中、または書込中の場合は `true`。
    private func isOpen(_ status: Stream.Status) -> Bool {
        switch status {
        case .open, .reading, .writing:
            true
        default:
            false
        }
    }

    /// Foundationストリームが継続可能な状態かを検証します。
    ///
    /// 責務: 1件のストリーム終了またはエラー状態を型付き通信失敗へ変換します。
    /// - Parameter stream: 状態を検証する入力または出力ストリーム。
    /// - Throws: エラー、終端、閉鎖状態の場合は `VehicleIdentificationError.connectionFailed`。
    private func validate(_ stream: Stream) throws {
        switch stream.streamStatus {
        case .error, .atEnd, .closed:
            throw VehicleIdentificationError.connectionFailed
        default:
            break
        }
    }

    /// 受信済みバイトから最初のELM/STNプロンプト境界を切り出します。
    ///
    /// 責務: 未返却受信バッファを最初の `>` を含む応答と後続バイトへ分割します。
    /// - Returns: 完全なプロンプト境界がある場合の応答。未完了の場合は `nil`。
    private func extractPromptResponse() -> Data? {
        guard let promptIndex = readBuffer.firstIndex(of: 0x3E) else { return nil }
        let responseEnd = readBuffer.index(after: promptIndex)
        let response = Data(readBuffer[..<responseEnd])
        readBuffer.removeSubrange(..<responseEnd)
        return response
    }

    /// セッションに属する全ストリーム参照を閉じて破棄します。
    ///
    /// 責務: 現在のExternalAccessory通信資源を再利用不能な未接続状態へ戻します。
    private func closeStreams() {
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        session = nil
        readBuffer.removeAll(keepingCapacity: false)
    }
}
#endif
