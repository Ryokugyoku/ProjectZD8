#if os(macOS)
import Foundation
import IOBluetooth
import OSLog

/// Bluetooth ClassicのSerial Port ProfileをELM/STNバイトストリームとして扱います。
actor MacOSBluetoothRFCOMMOBDTransport: OBDCommandTransport {
    /// 個人識別値や応答本文を含めず通信境界の失敗段階だけを記録します。
    nonisolated private static let logger = Logger(
        subsystem: "Ryokugyoku.ProjectZD8",
        category: "OBDBluetoothRFCOMMTransport"
    )

    /// 接続対象のBluetoothアドレスです。
    private let deviceAddress: String

    /// 1応答を待つ最大時間です。
    private let responseTimeout: Duration

    /// IOBluetoothのコールバックとRFCOMMチャネルを所有するドライバーです。
    private let driver = MacOSBluetoothRFCOMMChannelDriver()

    /// Bluetoothアドレスと応答期限を保持して生成します。
    ///
    /// 責務: 1件のBluetooth Classic終端に必要なRFCOMM接続設定を固定します。
    /// - Parameters:
    ///   - deviceAddress: macOSが返した接続対象のBluetoothアドレス。
    ///   - responseTimeout: `>` プロンプトを待つ最大時間。
    init(deviceAddress: String, responseTimeout: Duration = .seconds(12)) {
        self.deviceAddress = deviceAddress
        self.responseTimeout = responseTimeout
    }

    /// ペアリング済み機器のSerial Port Profileを照会してRFCOMMチャネルを開きます。
    ///
    /// 責務: 1件のBluetoothアドレスを動的に解決したSerial Port Profileチャネルへ接続します。
    /// - Throws: アドレス不正、未ペアリング、SDP照会、またはRFCOMM接続に失敗した場合は識別接続エラー。
    func open() async throws {
        do {
            try await driver.open(deviceAddress: deviceAddress)
            Self.logger.info("Bluetooth RFCOMM boundary opened")
        } catch {
            Self.logger.error("Bluetooth RFCOMM open failed")
            throw VehicleIdentificationError.connectionFailed
        }
    }

    /// 完全なASCIIコマンドをRFCOMMチャネルへ書き込みます。
    ///
    /// 責務: 1件のコマンドに属する全バイトをRFCOMMのMTU境界を守って送信します。
    /// - Parameter data: 復帰文字終端のASCIIコマンド。
    /// - Throws: 未接続または書込み失敗の場合は識別接続エラー。
    func write(_ data: Data) async throws {
        do {
            try driver.write(data)
        } catch {
            Self.logger.error("Bluetooth RFCOMM write failed")
            throw VehicleIdentificationError.connectionFailed
        }
    }

    /// 次のELM/STNプロンプトまでRFCOMM受信バイトを読み取ります。
    ///
    /// 責務: 現在コマンドのRFCOMM応答を最初の `>` 境界まで欠落なく収集します。
    /// - Returns: `>` を含む加工前応答。
    /// - Throws: 期限切れ、取消し、または切断の場合は型付き識別エラー。
    func readUntilPrompt() async throws -> Data {
        let deadline = ContinuousClock.now.advanced(by: responseTimeout)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let response = driver.takeResponseThroughPrompt() {
                return response
            }
            guard !driver.isClosed else {
                throw VehicleIdentificationError.connectionFailed
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Self.logger.error("Bluetooth RFCOMM response timed out")
        throw VehicleIdentificationError.responseTimedOut
    }

    /// 開いているRFCOMMチャネルを閉じます。
    ///
    /// 責務: 現在のBluetooth Classic接続を1回だけ閉じて受信状態を破棄します。
    func close() async {
        driver.close()
        Self.logger.info("Bluetooth RFCOMM boundary closed")
    }
}

/// IOBluetoothのRFCOMMチャネルとコールバック受信バッファを同期保護します。
private final class MacOSBluetoothRFCOMMChannelDriver: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    /// Serial Port Profileの標準16-bit UUIDです。
    private static let serialPortServiceUUID = IOBluetoothSDPUUID.uuid16(0x1101)

    /// チャネル、受信バッファ、SDP継続を保護するロックです。
    private let lock = NSLock()

    /// 現在開いているRFCOMMチャネルです。
    private var channel: IOBluetoothRFCOMMChannel?

    /// プロンプト境界まで保持する未消費受信バイトです。
    private var receiveBuffer = Data()

    /// 現在のチャネルが閉じているかどうかです。
    private var closed = true

    /// 非同期SDP照会の完了を待つ継続です。
    private var sdpContinuation: CheckedContinuation<Void, any Error>?

    /// 空のRFCOMMドライバーを生成します。
    ///
    /// 責務: Bluetoothチャネルをまだ所有しない同期済み受信状態を構築します。
    nonisolated override init() {
        super.init()
    }

    /// Bluetoothアドレスに対応するSerial Port Profileを解決して開きます。
    ///
    /// 責務: 1件のペアリング済みBluetooth機器をSDP解決済みRFCOMMチャネルへ変換します。
    /// - Parameter deviceAddress: macOS形式のBluetoothアドレス。
    /// - Throws: 機器、ペアリング、Serial Port Profile、またはチャネル接続を利用できない場合。
    func open(deviceAddress: String) async throws {
        guard let device = IOBluetoothDevice(addressString: deviceAddress),
              device.isPaired() else {
            throw MacOSBluetoothRFCOMMError.deviceUnavailable
        }

        if serialPortRecord(for: device) == nil {
            try await querySerialPortService(on: device)
        }
        guard let serviceRecord = serialPortRecord(for: device) else {
            throw MacOSBluetoothRFCOMMError.serialPortServiceUnavailable
        }

        var channelID: BluetoothRFCOMMChannelID = 0
        guard serviceRecord.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            throw MacOSBluetoothRFCOMMError.serialPortServiceUnavailable
        }

        var openedChannel: IOBluetoothRFCOMMChannel?
        guard device.openRFCOMMChannelSync(
            &openedChannel,
            withChannelID: channelID,
            delegate: self
        ) == kIOReturnSuccess, let openedChannel else {
            throw MacOSBluetoothRFCOMMError.channelOpenFailed
        }

        lock.withLock {
            channel = openedChannel
            receiveBuffer.removeAll(keepingCapacity: true)
            closed = false
        }
    }

    /// 現在チャネルへ全バイトを書き込みます。
    ///
    /// 責務: 1件のデータをRFCOMM MTU以下の連続チャンクへ分割して同期送信します。
    /// - Parameter data: 送信する完全なコマンドバイト。
    /// - Throws: 未接続またはいずれかのチャンク送信に失敗した場合。
    func write(_ data: Data) throws {
        let activeChannel = lock.withLock { channel }
        guard let activeChannel, activeChannel.isOpen() else {
            throw MacOSBluetoothRFCOMMError.channelClosed
        }
        let maximumChunkSize = min(Int(activeChannel.getMTU()), Int(UInt16.max))
        guard maximumChunkSize > 0 else {
            throw MacOSBluetoothRFCOMMError.writeFailed
        }

        var offset = 0
        while offset < data.count {
            var chunk = Data(data[offset..<min(offset + maximumChunkSize, data.count)])
            let result = chunk.withUnsafeMutableBytes { bytes -> IOReturn in
                activeChannel.writeSync(bytes.baseAddress, length: UInt16(bytes.count))
            }
            guard result == kIOReturnSuccess else {
                throw MacOSBluetoothRFCOMMError.writeFailed
            }
            offset += chunk.count
        }
    }

    /// 最初のプロンプトまでの受信済みバイトを取り出します。
    ///
    /// 責務: 同期保護された受信バッファから最初の `>` を含む1応答だけを消費します。
    /// - Returns: 完成した1応答。プロンプト未受信の場合は `nil`。
    func takeResponseThroughPrompt() -> Data? {
        lock.withLock {
            guard let promptIndex = receiveBuffer.firstIndex(of: 0x3E) else {
                return nil
            }
            let endIndex = receiveBuffer.index(after: promptIndex)
            let response = Data(receiveBuffer[..<endIndex])
            receiveBuffer.removeSubrange(..<endIndex)
            return response
        }
    }

    /// チャネルが閉じているかどうかです。
    var isClosed: Bool {
        lock.withLock { closed }
    }

    /// 現在のRFCOMMチャネルと保留状態を閉じます。
    ///
    /// 責務: 所有中のRFCOMMチャネルを閉じて受信状態を初期化します。
    func close() {
        let activeChannel = lock.withLock { () -> IOBluetoothRFCOMMChannel? in
            let result = channel
            channel = nil
            receiveBuffer.removeAll(keepingCapacity: false)
            closed = true
            return result
        }
        _ = activeChannel?.close()
    }

    /// RFCOMMから到着したバイトを受信バッファへコピーします。
    ///
    /// 責務: 1件のIOBluetooth受信通知が有効な間にバイト列を所有バッファへ複製します。
    /// - Parameters:
    ///   - rfcommChannel: 受信元のRFCOMMチャネル。
    ///   - dataPointer: コールバック期間だけ有効な受信バイト先頭。
    ///   - dataLength: 受信バイト数。
    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        let received = Data(bytes: dataPointer, count: dataLength)
        lock.withLock {
            receiveBuffer.append(received)
        }
    }

    /// RFCOMM切断通知を現在の接続状態へ反映します。
    ///
    /// 責務: 1件のチャネル切断通知を読取側が検出できる閉鎖状態へ変換します。
    /// - Parameter rfcommChannel: 閉じたRFCOMMチャネル。
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        lock.withLock {
            channel = nil
            closed = true
        }
    }

    /// SDP照会完了を待機中の接続処理へ通知します。
    ///
    /// 責務: 1件のIOBluetooth SDP完了通知を成功または照会失敗として再開します。
    /// - Parameters:
    ///   - device: 照会対象のBluetooth機器。
    ///   - status: IOBluetoothが返した照会結果。
    @objc
    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        finishSDPQuery(
            with: status == kIOReturnSuccess
                ? .success(())
                : .failure(MacOSBluetoothRFCOMMError.serviceQueryFailed)
        )
    }

    /// 機器のキャッシュ済みSerial Port Profileレコードを返します。
    ///
    /// 責務: 1件のBluetooth機器から標準Serial Port Profileサービスだけを選択します。
    /// - Parameter device: SDPサービスを保持するBluetooth機器。
    /// - Returns: Serial Port Profileレコード。未照会または非対応の場合は `nil`。
    private func serialPortRecord(for device: IOBluetoothDevice) -> IOBluetoothSDPServiceRecord? {
        guard let uuid = Self.serialPortServiceUUID else { return nil }
        return device.getServiceRecord(for: uuid)
    }

    /// Serial Port Profileだけを対象にSDP照会を開始して完了を待ちます。
    ///
    /// 責務: 1件のBluetooth機器に対するSerial Port Profile照会を期限付き非同期処理へ変換します。
    /// - Parameter device: 照会対象のペアリング済みBluetooth機器。
    /// - Throws: 照会開始、照会結果、または10秒の期限切れの場合。
    private func querySerialPortService(on device: IOBluetoothDevice) async throws {
        guard let uuid = Self.serialPortServiceUUID else {
            throw MacOSBluetoothRFCOMMError.serialPortServiceUnavailable
        }
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                sdpContinuation = continuation
            }
            let result = device.performSDPQuery(self, uuids: [uuid])
            guard result == kIOReturnSuccess else {
                finishSDPQuery(with: .failure(MacOSBluetoothRFCOMMError.serviceQueryFailed))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finishSDPQuery(with: .failure(MacOSBluetoothRFCOMMError.serviceQueryTimedOut))
            }
        }
    }

    /// 保留中のSDP継続を1回だけ完了します。
    ///
    /// 責務: 最初に到着したSDP結果だけで接続待機処理を再開します。
    /// - Parameter result: SDP照会の成功または失敗。
    private func finishSDPQuery(with result: Result<Void, any Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            let result = sdpContinuation
            sdpContinuation = nil
            return result
        }
        continuation?.resume(with: result)
    }
}

/// macOS Bluetooth Classic接続境界で区別する内部失敗です。
private enum MacOSBluetoothRFCOMMError: Error {
    /// 対象機器が存在しないかペアリングされていません。
    case deviceUnavailable
    /// Serial Port Profileを利用できません。
    case serialPortServiceUnavailable
    /// SDP照会を開始または完了できませんでした。
    case serviceQueryFailed
    /// SDP照会が期限内に完了しませんでした。
    case serviceQueryTimedOut
    /// RFCOMMチャネルを開けませんでした。
    case channelOpenFailed
    /// RFCOMMチャネルが閉じています。
    case channelClosed
    /// RFCOMM書込みに失敗しました。
    case writeFailed
}
#endif
