#if os(iOS)
import CoreBluetooth
import Foundation

/// CoreBluetoothを使ってiPhone周辺のBluetooth Low Energy候補を一定時間探索します。
@MainActor
final class IOSCoreBluetoothAdapterDiscovery: NSObject, AdapterDiscoveryPort, CBCentralManagerDelegate {
    /// CoreBluetooth検出値をDomain候補へ変換します。
    private let mapper = IOSBluetoothAdvertisementMapper()

    /// 現在の探索を担当する中央マネージャーです。
    private var centralManager: CBCentralManager?

    /// 現在の探索でPeripheral UUIDごとに保持する候補です。
    private var discoveredAdapters: [UUID: DiscoveredAdapter] = [:]

    /// 現在の非同期探索を完了させる継続です。
    private var discoveryContinuation: CheckedContinuation<[DiscoveredAdapter], any Error>?

    /// Bluetooth状態確定に設ける終了タスクです。
    private var stateTimeoutTask: Task<Void, Never>?

    /// BLEスキャン期間に設ける終了タスクです。
    private var scanTimeoutTask: Task<Void, Never>?

    /// 空の探索状態でCoreBluetooth探索境界を生成します。
    ///
    /// 責務: iOS向けBLE探索を開始前の状態で構築します。
    override init() {
        super.init()
    }

    /// Bluetooth Low Energy接続方式だけで周辺候補を取得します。
    ///
    /// 責務: iOSで許可されたBluetooth Low Energy探索要求を期限付きスキャンへ委譲します。
    /// - Parameter mode: 探索対象の物理接続方式。
    /// - Returns: スキャン期間内にCoreBluetoothから取得できた候補。
    /// - Throws: USB要求、Bluetooth利用不可、またはタスクキャンセルの場合のエラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        guard mode == .bluetooth else {
            throw AdapterDiscoveryError.transportUnsupported
        }
        return try await scan()
    }

    /// CoreBluetoothの状態確定と一定時間のBLEスキャンを非同期に実行します。
    ///
    /// 責務: 1回のキャンセル可能なBLE探索を開始し、終了条件に達した候補一覧を返します。
    /// - Returns: Peripheral UUIDごとに重複を除いたBLE候補。
    /// - Throws: Bluetooth利用不可またはタスクキャンセルの場合のエラー。
    /// - Side Effects: Bluetoothがオフの場合はシステムの電源確認アラートを表示できます。
    private func scan() async throws -> [DiscoveredAdapter] {
        try Task.checkCancellation()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                cancelActiveDiscovery()
                discoveredAdapters = [:]
                discoveryContinuation = continuation
                centralManager = CBCentralManager(
                    delegate: self,
                    queue: .main,
                    options: [CBCentralManagerOptionShowPowerAlertKey: true]
                )
                stateTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.finishDiscovery(with: .failure(AdapterDiscoveryError.bluetoothStateUnavailable))
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finishDiscovery(with: .failure(CancellationError()))
            }
        }
    }

    /// Bluetooth中央マネージャーの状態を現在の探索へ反映します。
    ///
    /// 責務: 1件のCoreBluetooth状態通知をスキャン開始または区別可能な利用不可結果へ変換します。
    /// - Parameter central: 状態が更新された中央マネージャー。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard discoveryContinuation != nil else { return }

        switch central.state {
        case .poweredOn:
            startScanning(with: central)
        case .poweredOff:
            finishDiscovery(with: .failure(AdapterDiscoveryError.bluetoothPoweredOff))
        case .unauthorized:
            finishDiscovery(with: .failure(AdapterDiscoveryError.bluetoothUnauthorized))
        case .unsupported:
            finishDiscovery(with: .failure(AdapterDiscoveryError.bluetoothUnsupported))
        case .unknown, .resetting:
            break
        @unknown default:
            finishDiscovery(with: .failure(AdapterDiscoveryError.bluetoothStateUnavailable))
        }
    }

    /// Bluetooth Low Energy周辺機器の検出情報をUUID単位で記録します。
    ///
    /// 責務: 1件のCoreBluetooth検出通知を名称優先順位と広告情報を保持する候補へ変換します。
    /// - Parameters:
    ///   - central: 検出通知を生成した中央マネージャー。
    ///   - peripheral: 検出されたBluetooth Low Energy周辺機器。
    ///   - advertisementData: 周辺機器が公開したアドバタイズ情報。
    ///   - RSSI: 検出時の受信信号強度。
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let adapter = mapper.makeAdapter(
            peripheralIdentifier: peripheral.identifier,
            advertisementLocalName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            peripheralName: peripheral.name,
            connectionState: connectionState(for: peripheral.state),
            hasManufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] != nil,
            serviceIdentifiers: advertisedServiceIdentifiers(from: advertisementData)
        )
        discoveredAdapters[peripheral.identifier] = adapter
    }

    /// BLE広告から通常およびOverflow Service UUIDを取得します。
    ///
    /// 責務: 1件のCoreBluetooth広告辞書を表示可能なService UUID文字列一覧へ変換します。
    /// - Parameter advertisementData: CoreBluetoothが公開した広告辞書。
    /// - Returns: 広告に含まれる通常およびOverflow Service UUID一覧。
    private func advertisedServiceIdentifiers(from advertisementData: [String: Any]) -> [String] {
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        return (advertised + overflow).map(\.uuidString)
    }

    /// 中央マネージャーで期限付きBLEスキャンを開始します。
    ///
    /// 責務: Bluetooth利用可能状態からSwiftOBD2と同じ1回の10秒間スキャンへ遷移します。
    /// - Parameter central: Bluetooth利用可能状態の中央マネージャー。
    private func startScanning(with central: CBCentralManager) {
        guard !central.isScanning else { return }
        stateTimeoutTask?.cancel()
        stateTimeoutTask = nil
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            finishDiscovery(with: .success(Array(discoveredAdapters.values)))
        }
    }

    /// CoreBluetooth接続状態をDomainの検出時状態へ変換します。
    ///
    /// 責務: 1件の `CBPeripheralState` をフレームワーク非依存の接続状態へ写像します。
    /// - Parameter state: CoreBluetoothから取得した周辺機器状態。
    /// - Returns: Domainが保持する検出時接続状態。
    private func connectionState(for state: CBPeripheralState) -> DiscoveredAdapterConnectionState {
        switch state {
        case .disconnected:
            .disconnected
        case .connecting:
            .connecting
        case .connected:
            .connected
        case .disconnecting:
            .disconnecting
        @unknown default:
            .unknown
        }
    }

    /// 現在の探索を停止して待機中の呼び出しへ結果を返します。
    ///
    /// 責務: 1回のBLE探索に属するCoreBluetooth処理と期限タスクを単一結果で完了します。
    /// - Parameter result: 探索呼び出しへ返す候補一覧またはエラー。
    private func finishDiscovery(with result: Result<[DiscoveredAdapter], any Error>) {
        guard let continuation = discoveryContinuation else { return }
        centralManager?.stopScan()
        stateTimeoutTask?.cancel()
        scanTimeoutTask?.cancel()
        stateTimeoutTask = nil
        scanTimeoutTask = nil
        centralManager = nil
        discoveryContinuation = nil
        continuation.resume(with: result)
    }

    /// 進行中の探索があればキャンセル結果で完了します。
    ///
    /// 責務: 新しい探索前に以前のBLE探索境界を確実に終了します。
    private func cancelActiveDiscovery() {
        finishDiscovery(with: .failure(CancellationError()))
    }
}
#endif
