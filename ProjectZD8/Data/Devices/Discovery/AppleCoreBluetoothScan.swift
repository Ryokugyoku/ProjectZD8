#if os(iOS) || os(macOS)
import CoreBluetooth
import Foundation

/// 1回分のBLEスキャンを担当する使い捨てのセッションです。
@MainActor
final class AppleCoreBluetoothScan: NSObject, CBCentralManagerDelegate {
    /// CoreBluetooth検出値をアダプター記述へ変換します。
    private let mapper = AppleBluetoothAdvertisementMapper()

    /// BLE候補を既知OBDアダプターへ限定する判定規則です。
    private let candidatePolicy = AppleOBDBluetoothCandidatePolicy()

    /// 現在の探索を担当する中央マネージャーです。
    private var centralManager: CBCentralManager?

    /// Peripheral UUIDごとに保持する候補です。
    private var discoveredAdapters: [UUID: AdapterDescriptor] = [:]

    /// 非同期探索を完了させる継続です。
    private var discoveryContinuation: CheckedContinuation<[AdapterDescriptor], any Error>?

    /// Bluetooth状態確定に設ける終了タスクです。
    private var stateTimeoutTask: Task<Void, Never>?

    /// BLEスキャン期間に設ける終了タスクです。
    private var scanTimeoutTask: Task<Void, Never>?

    /// 責務: 状態確定の待機とスキャンを1回実行し、終了条件に達した候補一覧を返します。
    /// - Throws: Bluetooth利用不可またはタスク取消し。
    /// - Side Effects: Bluetoothがオフの場合はシステムの電源確認アラートを表示できます。
    func run() async throws -> [AdapterDescriptor] {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                discoveryContinuation = continuation
                centralManager = CBCentralManager(
                    delegate: self,
                    queue: .main,
                    options: [CBCentralManagerOptionShowPowerAlertKey: true]
                )
                stateTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self?.finish(with: .failure(AdapterDiscoveryError.failed))
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finish(with: .failure(CancellationError()))
            }
        }
    }

    /// 責務: 1件のCoreBluetooth状態通知をスキャン開始または区別可能な失敗へ変換します。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard discoveryContinuation != nil else { return }
        switch central.state {
        case .poweredOn:
            startScanning(with: central)
        case .poweredOff:
            finish(with: .failure(AdapterDiscoveryError.bluetoothPoweredOff))
        case .unauthorized:
            finish(with: .failure(AdapterDiscoveryError.bluetoothUnauthorized))
        case .unsupported:
            finish(with: .failure(AdapterDiscoveryError.bluetoothUnsupported))
        case .unknown, .resetting:
            break
        @unknown default:
            finish(with: .failure(AdapterDiscoveryError.failed))
        }
    }

    /// 責務: 1件の検出通知を既知OBD信号で選別して候補として保持します。
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisement = BluetoothAdvertisement(
            peripheralIdentifier: peripheral.identifier,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            peripheralName: peripheral.name,
            serviceIdentifiers: advertisedServiceIdentifiers(from: advertisementData)
        )
        guard candidatePolicy.accepts(advertisement) else { return }
        discoveredAdapters[peripheral.identifier] = mapper.makeAdapter(from: advertisement)
    }

    /// 責務: 広告辞書の通常およびOverflow Service UUIDを文字列一覧へ変換します。
    private func advertisedServiceIdentifiers(from advertisementData: [String: Any]) -> [String] {
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        return (advertised + overflow).map(\.uuidString)
    }

    /// 責務: Bluetooth利用可能状態から1回の10秒間スキャンを開始します。
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
            finish(with: .success(Array(discoveredAdapters.values)))
        }
    }

    /// 責務: スキャンと期限タスクを止め、待機中の呼び出しへ結果を1回だけ返します。
    private func finish(with result: Result<[AdapterDescriptor], any Error>) {
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
}
#endif
