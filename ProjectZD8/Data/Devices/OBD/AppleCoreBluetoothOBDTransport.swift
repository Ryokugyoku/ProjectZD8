#if os(iOS) || os(macOS)
import CoreBluetooth
import Foundation
import OSLog

/// 選択済みBLE Peripheralを既知UART構成へ接続してELM/STNバイトストリームを提供します。
@MainActor
final class AppleCoreBluetoothOBDTransport: NSObject, OBDCommandTransport, CBCentralManagerDelegate, CBPeripheralDelegate {
    /// 接続対象のPeripheral UUIDと表示名です。
    private let endpoint: OBDConnectionEndpoint
    /// 実機能力を既知UART構成へ照合します。
    private let profileResolver = AppleBluetoothUARTProfileResolver()
    /// 実機で発見したUUIDを機密値なしで記録します。
    private let logger = Logger(subsystem: "ProjectZD8", category: "AppleCoreBluetoothOBDTransport")
    /// 現在のBLE中央役割です。
    private var centralManager: CBCentralManager?
    /// 現在接続または探索しているPeripheralです。
    private var peripheral: CBPeripheral?
    /// アダプターへ送信するCharacteristicです。
    private var writeCharacteristic: CBCharacteristic?
    /// アダプターから通知を受けるCharacteristicです。
    private var notifyCharacteristic: CBCharacteristic?
    /// Service探索中に取得したCharacteristic一覧です。
    private var characteristicsByService: [CBUUID: [CBCharacteristic]] = [:]
    /// 完了待ちのService別Characteristic探索数です。
    private var pendingCharacteristicDiscoveries = 0
    /// `open()`を完了する継続です。
    private var openContinuation: CheckedContinuation<Void, any Error>?
    /// 応答あり書込を完了する継続です。
    private var writeContinuation: CheckedContinuation<Void, any Error>?
    /// `>`終端応答を返す継続です。
    private var readContinuation: CheckedContinuation<Data, any Error>?
    /// Notifyで分割受信した未返却バイトです。
    private var readBuffer = Data()
    /// 接続処理の期限タスクです。
    private var openTimeoutTask: Task<Void, Never>?
    /// 応答あり書込の期限タスクです。
    private var writeTimeoutTask: Task<Void, Never>?
    /// プロンプト読取の期限タスクです。
    private var readTimeoutTask: Task<Void, Never>?

    /// 選択済みBluetooth Low Energy終端を固定して生成します。
    ///
    /// 責務: 1件のBLE終端をCoreBluetooth UART接続条件へ固定します。
    /// - Parameter endpoint: Peripheral UUIDを持つ選択済みBLE終端。
    /// - Throws: BLE以外またはUUID不正の場合は `VehicleIdentificationError.transportUnsupported`。
    init(endpoint: OBDConnectionEndpoint) throws {
        guard endpoint.transport == .bluetoothLowEnergy,
              UUID(uuidString: endpoint.systemIdentifier) != nil else {
            throw VehicleIdentificationError.transportUnsupported
        }
        self.endpoint = endpoint
        super.init()
    }

    /// 選択済みPeripheralへ接続して既知UART Characteristicの通知を有効化します。
    ///
    /// 責務: 1件の選択済みBLE PeripheralをNotify／Write可能な既知UARTセッションへ遷移させます。
    /// - Throws: Bluetooth利用不可、Peripheral不在、接続失敗、未知UUID構成、または期限切れの場合の識別エラー。
    /// - Side Effects: Bluetoothがオフの場合はシステムの電源確認アラートを表示できます。
    func open() async throws {
        if peripheral?.state == .connected,
           writeCharacteristic != nil,
           notifyCharacteristic?.isNotifying == true {
            return
        }
        guard openContinuation == nil else {
            throw VehicleIdentificationError.connectionFailed
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                resetConnectionState()
                openContinuation = continuation
                centralManager = CBCentralManager(
                    delegate: self,
                    queue: .main,
                    options: [CBCentralManagerOptionShowPowerAlertKey: true]
                )
                openTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled else { return }
                    self?.failConnection(with: VehicleIdentificationError.responseTimedOut)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failConnection(with: CancellationError())
            }
        }
    }

    /// 復帰文字を含むELM/STNコマンドをMTUに収まる単位で書き込みます。
    ///
    /// 責務: 1件の完全なコマンドバイト列をCharacteristic能力と最大書込長に従って順次送信します。
    /// - Parameter data: 復帰文字を含む完全なASCIIコマンド。
    /// - Throws: 未接続、書込能力欠損、切断、または期限切れの場合の識別エラー。
    func write(_ data: Data) async throws {
        guard let peripheral,
              peripheral.state == .connected,
              let writeCharacteristic else {
            throw VehicleIdentificationError.connectionFailed
        }
        let writeType = try selectedWriteType(for: writeCharacteristic)
        let maximumLength = max(1, peripheral.maximumWriteValueLength(for: writeType))
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            let end = min(data.count, offset + maximumLength)
            let chunk = Data(data[offset..<end])
            switch writeType {
            case .withResponse:
                try await writeWithResponse(
                    chunk,
                    to: writeCharacteristic,
                    peripheral: peripheral
                )
            case .withoutResponse:
                try await waitUntilReadyForWriteWithoutResponse(peripheral)
                peripheral.writeValue(chunk, for: writeCharacteristic, type: .withoutResponse)
            @unknown default:
                throw VehicleIdentificationError.transportUnsupported
            }
            offset = end
        }
    }

    /// Notifyで受信したバイトを次のELM/STNプロンプトまで返します。
    ///
    /// 責務: 分割されたBLE通知を1件の `>` プロンプト終端応答へ結合します。
    /// - Returns: `>`を含む加工前応答バイト。
    /// - Throws: 同時読取、未接続、切断、通知エラー、または期限切れの場合の識別エラー。
    func readUntilPrompt() async throws -> Data {
        if let response = extractPromptResponse() {
            return response
        }
        guard peripheral?.state == .connected,
              notifyCharacteristic?.isNotifying == true,
              readContinuation == nil else {
            throw VehicleIdentificationError.connectionFailed
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                readContinuation = continuation
                readTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    self?.finishRead(with: .failure(VehicleIdentificationError.responseTimedOut))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishRead(with: .failure(CancellationError()))
            }
        }
    }

    /// 現在のCoreBluetooth接続と待機中の送受信を終了します。
    ///
    /// 責務: 1件のBLE UARTセッションに属するCoreBluetooth資源と未返却バイトを破棄します。
    func close() async {
        failPendingOperations(with: VehicleIdentificationError.connectionFailed)
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        resetConnectionState()
        centralManager = nil
    }

    /// Bluetooth中央マネージャーの状態を接続開始または失敗へ変換します。
    ///
    /// 責務: 1件のCoreBluetooth状態通知を選択済みPeripheralの再取得または型付き失敗へ変換します。
    /// - Parameter central: 状態が更新された中央マネージャー。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard openContinuation != nil else { return }
        switch central.state {
        case .poweredOn:
            locateSelectedPeripheral(using: central)
        case .poweredOff, .unauthorized, .unsupported:
            failConnection(with: VehicleIdentificationError.connectionFailed)
        case .unknown, .resetting:
            break
        @unknown default:
            failConnection(with: VehicleIdentificationError.connectionFailed)
        }
    }

    /// スキャンで選択済みUUIDと一致したPeripheralへ接続します。
    ///
    /// 責務: 1件のBLE広告を選択済みPeripheral UUIDと照合して接続要求へ進めます。
    /// - Parameters:
    ///   - central: 広告を受信した中央マネージャー。
    ///   - peripheral: 検出されたPeripheral。
    ///   - advertisementData: 実装では接続判断に使用しない広告値。
    ///   - RSSI: 実装では接続判断に使用しない受信強度。
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard peripheral.identifier.uuidString.caseInsensitiveCompare(endpoint.systemIdentifier) == .orderedSame else {
            return
        }
        central.stopScan()
        connect(peripheral, using: central)
    }

    /// Peripheral接続後に全Service探索を開始します。
    ///
    /// 責務: 1件の接続済みPeripheralをService能力探索へ遷移させます。
    /// - Parameters:
    ///   - central: 接続を完了した中央マネージャー。
    ///   - peripheral: 接続済みPeripheral。
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    /// Peripheral接続失敗を待機中処理へ返します。
    ///
    /// 責務: 1件のCoreBluetooth接続失敗を型付き通信失敗として接続処理へ返します。
    /// - Parameters:
    ///   - central: 接続を試行した中央マネージャー。
    ///   - peripheral: 接続できなかったPeripheral。
    ///   - error: CoreBluetoothが報告した任意エラー。
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        failConnection(with: VehicleIdentificationError.connectionFailed)
    }

    /// Peripheral切断を待機中の接続または送受信へ返します。
    ///
    /// 責務: 1件の予期しないBLE切断を全待機処理の通信失敗へ変換します。
    /// - Parameters:
    ///   - central: 切断を報告した中央マネージャー。
    ///   - peripheral: 切断されたPeripheral。
    ///   - error: CoreBluetoothが報告した任意エラー。
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        failConnection(with: VehicleIdentificationError.connectionFailed)
    }

    /// 発見済みServiceごとに全Characteristic探索を開始します。
    ///
    /// 責務: 1件のService探索結果をUART能力判定に必要なCharacteristic探索群へ展開します。
    /// - Parameters:
    ///   - peripheral: Serviceを探索したPeripheral。
    ///   - error: CoreBluetoothが報告した任意エラー。
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            failConnection(with: VehicleIdentificationError.transportUnsupported)
            return
        }
        logger.info("BLE services: \(services.map(\.uuid.uuidString).joined(separator: ","), privacy: .public)")
        characteristicsByService = [:]
        pendingCharacteristicDiscoveries = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// 1件のServiceで発見したCharacteristic能力を記録します。
    ///
    /// 責務: Service別Characteristic探索結果を蓄積し全Service完了時に既知UART構成へ解決します。
    /// - Parameters:
    ///   - peripheral: Characteristicを探索したPeripheral。
    ///   - service: 探索対象Service。
    ///   - error: CoreBluetoothが報告した任意エラー。
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        characteristicsByService[service.uuid] = error == nil ? (service.characteristics ?? []) : []
        let identifiers = characteristicsByService[service.uuid, default: []].map(\.uuid.uuidString)
        logger.info("BLE characteristics \(service.uuid.uuidString, privacy: .public): \(identifiers.joined(separator: ","), privacy: .public)")
        pendingCharacteristicDiscoveries -= 1
        if pendingCharacteristicDiscoveries == 0 {
            resolveUARTCharacteristics(for: peripheral)
        }
    }

    /// Notify有効化結果を接続完了へ反映します。
    ///
    /// 責務: 選択済み通知Characteristicの購読結果をBLE UART接続の成否へ変換します。
    /// - Parameters:
    ///   - peripheral: Notify設定を行ったPeripheral。
    ///   - characteristic: 設定結果を持つCharacteristic。
    ///   - error: CoreBluetoothが報告した任意エラー。
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == notifyCharacteristic?.uuid,
              error == nil,
              characteristic.isNotifying else {
            failConnection(with: VehicleIdentificationError.connectionFailed)
            return
        }
        completeOpen()
    }

    /// 応答あり書込の完了を現在の書込処理へ返します。
    ///
    /// 責務: 選択済み書込CharacteristicのACKを1件の待機中チャンクへ返します。
    /// - Parameters:
    ///   - peripheral: 書込先Peripheral。
    ///   - characteristic: 書込結果を持つCharacteristic。
    ///   - error: CoreBluetoothが報告した任意エラー。
    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == writeCharacteristic?.uuid else { return }
        finishWrite(with: error == nil
            ? .success(())
            : .failure(VehicleIdentificationError.connectionFailed))
    }

    /// Notifyで受信した分割バイトを応答バッファへ追加します。
    ///
    /// 責務: 1件のCharacteristic通知を未返却バイトへ結合し完全なプロンプト応答を待機読取へ返します。
    /// - Parameters:
    ///   - peripheral: 通知元Peripheral。
    ///   - characteristic: 通知値を持つCharacteristic。
    ///   - error: CoreBluetoothが報告した任意エラー。
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard characteristic.uuid == notifyCharacteristic?.uuid else { return }
        guard error == nil, let value = characteristic.value else {
            finishRead(with: .failure(VehicleIdentificationError.connectionFailed))
            return
        }
        readBuffer.append(value)
        if readContinuation != nil, let response = extractPromptResponse() {
            finishRead(with: .success(response))
        }
    }

    /// 保存済みUUIDに対応するPeripheralをキャッシュまたはスキャンから再特定します。
    ///
    /// 責務: 選択済みPeripheral UUIDをCoreBluetooth接続対象へ解決します。
    /// - Parameter central: Powered On状態の中央マネージャー。
    private func locateSelectedPeripheral(using central: CBCentralManager) {
        guard let identifier = UUID(uuidString: endpoint.systemIdentifier) else {
            failConnection(with: VehicleIdentificationError.transportUnsupported)
            return
        }
        if let known = central.retrievePeripherals(withIdentifiers: [identifier]).first {
            connect(known, using: central)
        } else {
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    /// 指定Peripheralへ1回だけ接続要求を送ります。
    ///
    /// 責務: 再特定した1件のPeripheralを現在のCoreBluetooth接続対象へ固定します。
    /// - Parameters:
    ///   - peripheral: 接続対象Peripheral。
    ///   - central: 接続要求を実行する中央マネージャー。
    private func connect(_ peripheral: CBPeripheral, using central: CBCentralManager) {
        guard self.peripheral == nil else { return }
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    /// 発見済みCharacteristicを既知UART構成へ解決してNotifyを有効化します。
    ///
    /// 責務: 実機Service能力から書込先と通知元を1組だけ選びBLE UARTを準備します。
    /// - Parameter peripheral: 全Characteristic探索を完了したPeripheral。
    private func resolveUARTCharacteristics(for peripheral: CBPeripheral) {
        let capabilities = Dictionary(uniqueKeysWithValues: characteristicsByService.map { service, characteristics in
            (
                service.uuidString,
                characteristics.map { characteristic in
                    AppleBluetoothCharacteristicCapability(
                        uuid: characteristic.uuid.uuidString,
                        supportsNotify: characteristic.properties.contains(.notify)
                            || characteristic.properties.contains(.indicate),
                        supportsWriteWithResponse: characteristic.properties.contains(.write),
                        supportsWriteWithoutResponse: characteristic.properties.contains(.writeWithoutResponse)
                    )
                }
            )
        })
        guard let profile = profileResolver.resolve(services: capabilities),
              let serviceEntry = characteristicsByService.first(where: {
                  $0.key.uuidString.caseInsensitiveCompare(profile.serviceUUID) == .orderedSame
              }),
              let write = serviceEntry.value.first(where: {
                  $0.uuid.uuidString.caseInsensitiveCompare(profile.writeCharacteristicUUID) == .orderedSame
              }),
              let notify = serviceEntry.value.first(where: {
                  $0.uuid.uuidString.caseInsensitiveCompare(profile.notifyCharacteristicUUID) == .orderedSame
              }) else {
            failConnection(with: VehicleIdentificationError.transportUnsupported)
            return
        }
        logger.info("BLE UART profile: \(profile.kind.rawValue, privacy: .public)")
        writeCharacteristic = write
        notifyCharacteristic = notify
        peripheral.setNotifyValue(true, for: notify)
    }

    /// Characteristic能力に対応する安全な書込方式を選択します。
    ///
    /// 責務: 1件の書込CharacteristicからACK可能方式を優先した書込種別を決定します。
    /// - Parameter characteristic: 送信先Characteristic。
    /// - Returns: 応答あり、または対応時の応答なし書込種別。
    /// - Throws: どちらの書込能力もない場合は `VehicleIdentificationError.transportUnsupported`。
    private func selectedWriteType(for characteristic: CBCharacteristic) throws -> CBCharacteristicWriteType {
        if characteristic.properties.contains(.write) {
            return .withResponse
        }
        if characteristic.properties.contains(.writeWithoutResponse) {
            return .withoutResponse
        }
        throw VehicleIdentificationError.transportUnsupported
    }

    /// 1チャンクを応答ありで書き込みACKを待ちます。
    ///
    /// 責務: 1件のMTU内チャンクを書込Characteristicへ送り単一ACKまで待機します。
    /// - Parameters:
    ///   - data: MTU以内の送信バイト。
    ///   - characteristic: 書込先Characteristic。
    ///   - peripheral: 接続済みPeripheral。
    /// - Throws: 同時書込、CoreBluetooth書込失敗、または期限切れの場合の識別エラー。
    private func writeWithResponse(
        _ data: Data,
        to characteristic: CBCharacteristic,
        peripheral: CBPeripheral
    ) async throws {
        guard writeContinuation == nil else {
            throw VehicleIdentificationError.connectionFailed
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                writeContinuation = continuation
                writeTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    self?.finishWrite(with: .failure(VehicleIdentificationError.responseTimedOut))
                }
                peripheral.writeValue(data, for: characteristic, type: .withResponse)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishWrite(with: .failure(CancellationError()))
            }
        }
    }

    /// 応答なし書込キューが送信可能になるまで期限付きで待機します。
    ///
    /// 責務: 1件のPeripheral応答なし書込キューを次チャンク送信可能状態まで待機します。
    /// - Parameter peripheral: 接続済みPeripheral。
    /// - Throws: 切断、キャンセル、または期限切れの場合の識別エラー。
    private func waitUntilReadyForWriteWithoutResponse(_ peripheral: CBPeripheral) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !peripheral.canSendWriteWithoutResponse {
            try Task.checkCancellation()
            guard peripheral.state == .connected else {
                throw VehicleIdentificationError.connectionFailed
            }
            guard ContinuousClock.now < deadline else {
                throw VehicleIdentificationError.responseTimedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// BLE UART接続を成功として待機呼び出しへ返します。
    ///
    /// 責務: Notify有効化済みBLE UARTを1回の `open()` 成功として確定します。
    private func completeOpen() {
        guard let continuation = openContinuation else { return }
        openTimeoutTask?.cancel()
        openTimeoutTask = nil
        openContinuation = nil
        continuation.resume()
    }

    /// 接続失敗を全待機処理へ返してCoreBluetooth資源を閉じます。
    ///
    /// 責務: 1件のBLE接続失敗を未完了の接続、書込、読取へ伝播して接続状態を破棄します。
    /// - Parameter error: 各待機処理へ返す型付きまたはキャンセルエラー。
    private func failConnection(with error: any Error) {
        failPendingOperations(with: error)
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        resetConnectionState()
        centralManager = nil
    }

    /// 未完了の接続、書込、読取を同じ失敗で完了します。
    ///
    /// 責務: 現在のBLE UARTセッションに属する全継続を1件の失敗で終了します。
    /// - Parameter error: 未完了継続へ返すエラー。
    private func failPendingOperations(with error: any Error) {
        openTimeoutTask?.cancel()
        writeTimeoutTask?.cancel()
        readTimeoutTask?.cancel()
        openTimeoutTask = nil
        writeTimeoutTask = nil
        readTimeoutTask = nil
        let pendingOpen = openContinuation
        let pendingWrite = writeContinuation
        let pendingRead = readContinuation
        openContinuation = nil
        writeContinuation = nil
        readContinuation = nil
        pendingOpen?.resume(throwing: error)
        pendingWrite?.resume(throwing: error)
        pendingRead?.resume(throwing: error)
    }

    /// 応答あり書込継続へACK結果を返します。
    ///
    /// 責務: 1件の待機中書込をCoreBluetooth ACKの成功または失敗で完了します。
    /// - Parameter result: 書込ACK結果。
    private func finishWrite(with result: Result<Void, any Error>) {
        guard let continuation = writeContinuation else { return }
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil
        writeContinuation = nil
        continuation.resume(with: result)
    }

    /// 読取継続へプロンプト応答または失敗を返します。
    ///
    /// 責務: 1件の待機中プロンプト読取を完全応答または型付き失敗で完了します。
    /// - Parameter result: 完全応答または読取エラー。
    private func finishRead(with result: Result<Data, any Error>) {
        guard let continuation = readContinuation else { return }
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
        readContinuation = nil
        continuation.resume(with: result)
    }

    /// 未返却バッファから最初のELM/STNプロンプト境界を切り出します。
    ///
    /// 責務: BLE受信バッファを最初の `>` を含む応答と後続バイトへ分割します。
    /// - Returns: 完全なプロンプト境界がある場合の応答。未完了の場合は `nil`。
    private func extractPromptResponse() -> Data? {
        guard let promptIndex = readBuffer.firstIndex(of: 0x3E) else { return nil }
        let responseEnd = readBuffer.index(after: promptIndex)
        let response = Data(readBuffer[..<responseEnd])
        readBuffer.removeSubrange(..<responseEnd)
        return response
    }

    /// 接続オブジェクトと発見済み能力を未接続状態へ戻します。
    ///
    /// 責務: 現在のBLE Peripheral参照、Characteristic能力、受信バッファを破棄します。
    private func resetConnectionState() {
        centralManager?.stopScan()
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        characteristicsByService = [:]
        pendingCharacteristicDiscoveries = 0
        readBuffer.removeAll(keepingCapacity: false)
    }
}
#endif
