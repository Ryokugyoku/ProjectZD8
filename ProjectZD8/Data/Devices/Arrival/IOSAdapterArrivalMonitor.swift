#if os(iOS)
import CoreBluetooth
import Foundation

/// 保存済みの既定BLEアダプターが近くに現れたことを、既知UART Serviceの広告だけを手掛かりに検知し、通知でユーザーへ知らせます。
@MainActor
final class IOSAdapterArrivalMonitor: NSObject, AdapterArrivalMonitoringPort, CBCentralManagerDelegate {
    /// CoreBluetooth状態復元に使う安定識別子です。
    private static let restorationIdentifier = "ProjectZD8.default-adapter-arrival"

    /// バックグラウンドの探索を限定する既知UART Service UUIDです。
    private let serviceUUIDs: [CBUUID]
    /// 到来を知らせるローカル通知の提示境界です。
    private let notifier: IOSAdapterArrivalNotifier
    /// 到来監視に使う中央マネージャーです。
    private var centralManager: CBCentralManager?
    /// 現在監視している既定アダプターです。
    private var monitoredAdapter: AdapterDescriptor?
    /// 現在の監視世代で通知を配信済みかどうかです。
    private var hasDeliveredArrival = false
    /// 非同期の準備が古い監視要求のものかを見分ける世代番号です。
    private var generation = 0

    /// 通知境界を注入して生成します。通知応答を取りこぼさないよう、通知境界ごと起動完了前に生成してください。
    ///
    /// 責務: 既知UART Service集合を監視条件へ固定し、通知応答の受付を起動時に登録します。
    /// - Parameter notifier: 到来通知の提示境界。
    init(notifier: IOSAdapterArrivalNotifier) {
        self.notifier = notifier
        serviceUUIDs = AppleBluetoothUARTProfile.supported.map { CBUUID(string: $0.serviceUUID) }
        super.init()
    }

    /// 責務: 既定BLEアダプターの出現監視を開始します。通知が許可されていない場合は監視しません。
    /// - Side Effects: 初回は通知許可ダイアログを表示し、許可後に状態復元対応のBLEスキャンを開始します。
    func startMonitoring(_ adapter: AdapterDescriptor, onConnectRequested: @escaping @MainActor (AdapterDescriptor) -> Void) {
        stopMonitoring()
        guard adapter.transport == .bluetoothLowEnergy, UUID(uuidString: adapter.systemIdentifier) != nil else {
            return
        }
        monitoredAdapter = adapter
        let currentGeneration = generation
        Task { [weak self] in
            guard let self else { return }
            let isAllowed = await notifier.prepare(acceptance: onConnectRequested)
            guard isAllowed, currentGeneration == generation, monitoredAdapter != nil else { return }
            beginScanning()
        }
    }

    /// 責務: 出現監視とスキャンを止め、監視状態を空にします。
    func stopMonitoring() {
        generation += 1
        centralManager?.stopScan()
        centralManager = nil
        monitoredAdapter = nil
        hasDeliveredArrival = false
    }

    /// 責務: 中央マネージャーを(状態復元つきで)生成する、または既存のスキャンを再開します。
    private func beginScanning() {
        hasDeliveredArrival = false
        if let centralManager {
            restartScanIfAvailable(centralManager)
        } else {
            centralManager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [
                    CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier,
                    CBCentralManagerOptionShowPowerAlertKey: false
                ]
            )
        }
    }

    /// 責務: Bluetooth利用状態をスキャンの開始または停止へ反映します。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            restartScanIfAvailable(central)
        } else if central.isScanning {
            central.stopScan()
        }
    }

    /// 責務: 状態復元されたPeripheralから既定アダプターを探し、見つかれば通知します。
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        if let matched = peripherals.first(where: matchesMonitoredAdapter) {
            deliverArrival(for: matched)
        } else if central.state == .poweredOn {
            restartScanIfAvailable(central)
        }
    }

    /// 責務: 既知UART Serviceの広告を既定アダプターのUUIDと照合し、一致したら通知します。
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard matchesMonitoredAdapter(peripheral) else { return }
        central.stopScan()
        deliverArrival(for: peripheral)
    }

    /// 責務: Bluetooth利用可能時に既知UART Service限定のスキャンを開始し直します。
    private func restartScanIfAvailable(_ central: CBCentralManager) {
        guard monitoredAdapter != nil, !hasDeliveredArrival, central.state == .poweredOn else { return }
        if central.isScanning { central.stopScan() }
        central.scanForPeripherals(
            withServices: serviceUUIDs,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// 責務: Peripheralが監視中アダプターのUUIDと(大文字小文字を無視して)一致するかを返します。
    private func matchesMonitoredAdapter(_ peripheral: CBPeripheral) -> Bool {
        guard let monitoredAdapter else { return false }
        return peripheral.identifier.uuidString.caseInsensitiveCompare(monitoredAdapter.systemIdentifier) == .orderedSame
    }

    /// 責務: 一致したアダプターの到来を、監視世代ごとに高々1回だけ通知します。
    private func deliverArrival(for peripheral: CBPeripheral) {
        guard !hasDeliveredArrival, matchesMonitoredAdapter(peripheral), let monitoredAdapter else { return }
        hasDeliveredArrival = true
        centralManager?.stopScan()
        notifier.present(monitoredAdapter)
    }
}
#endif
