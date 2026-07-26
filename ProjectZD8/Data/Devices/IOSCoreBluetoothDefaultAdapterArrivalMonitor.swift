#if os(iOS)
import CoreBluetooth
import Foundation

/// 保存済みBLE Peripheralの広告を既知UART Serviceに限定して監視します。
@MainActor
final class IOSCoreBluetoothDefaultAdapterArrivalMonitor: NSObject,
    DefaultAdapterArrivalMonitoring,
    CBCentralManagerDelegate {
    /// CoreBluetooth状態復元に使用する安定識別子です。
    private static let restorationIdentifier = "ProjectZD8.default-adapter-arrival"

    /// バックグラウンド探索を限定する既知UART Service UUID一覧です。
    private let serviceUUIDs: [CBUUID]

    /// 到来監視に使用する中央マネージャーです。
    private var centralManager: CBCentralManager?

    /// 現在監視している既定アダプター設定です。
    private var preference: DefaultAdapterPreference?

    /// 対象Peripheralを検出したときの通知先です。
    private var arrival: (@MainActor (OBDConnectionEndpoint) -> Void)?

    /// 現在の監視世代で到来通知を送信済みかどうかです。
    private var hasDeliveredArrival = false

    /// 既知BLE UART Serviceを対象として監視境界を生成します。
    ///
    /// 責務: 製品が対応するUART Service集合をバックグラウンドBLE監視条件へ固定します。
    override init() {
        serviceUUIDs = IOSBluetoothUARTProfile.supported.map {
            CBUUID(string: $0.serviceUUID)
        }
        super.init()
    }

    /// 指定された既定BLE Peripheralの広告監視を開始します。
    ///
    /// 責務: 1件の既定BLE UUIDを既知UART Serviceに限定した継続探索へ反映します。
    /// - Parameters:
    ///   - preference: 監視対象の既定BLE設定。
    ///   - arrival: 対象Peripheralを検出したときの通知先。
    /// - Side Effects: CoreBluetoothの状態復元対応スキャンを開始します。
    func startMonitoring(
        preference: DefaultAdapterPreference,
        arrival: @escaping @MainActor (OBDConnectionEndpoint) -> Void
    ) {
        guard preference.connectionTransport == .bluetoothLowEnergy,
              UUID(uuidString: preference.systemIdentifier) != nil else {
            stopMonitoring()
            return
        }

        self.preference = preference
        self.arrival = arrival
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

    /// 現在のBLE広告監視と到来通知先を破棄します。
    ///
    /// 責務: 進行中の既定Peripheral探索を停止して監視状態を空にします。
    /// - Side Effects: CoreBluetoothのスキャンを停止します。
    func stopMonitoring() {
        centralManager?.stopScan()
        centralManager = nil
        preference = nil
        arrival = nil
        hasDeliveredArrival = false
    }

    /// Bluetooth利用状態を既定Peripheral探索の開始可否へ反映します。
    ///
    /// 責務: CoreBluetoothの状態更新を監視スキャンの開始または停止へ変換します。
    /// - Parameter central: 状態が更新された中央マネージャー。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            restartScanIfAvailable(central)
        } else if central.isScanning {
            central.stopScan()
        }
    }

    /// 状態復元された接続済みPeripheralを現在の既定設定と照合します。
    ///
    /// 責務: CoreBluetooth復元状態のPeripheral集合から既定BLE到来を高々1件通知します。
    /// - Parameters:
    ///   - central: 復元された中央マネージャー。
    ///   - dict: CoreBluetoothが保存していた状態辞書。
    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        if let matched = peripherals.first(where: matchesPreference) {
            deliverArrival(for: matched)
        } else if central.state == .poweredOn {
            restartScanIfAvailable(central)
        }
    }

    /// BLE広告を現在の既定Peripheral UUIDと照合します。
    ///
    /// 責務: 1件の既知UART Service広告から既定BLE到来だけを通知します。
    /// - Parameters:
    ///   - central: 広告を検出した中央マネージャー。
    ///   - peripheral: 広告元のPeripheral。
    ///   - advertisementData: 監視ではUUID照合以外に使用しない広告値。
    ///   - RSSI: 監視では使用しない受信信号強度。
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard matchesPreference(peripheral) else { return }
        central.stopScan()
        deliverArrival(for: peripheral)
    }

    /// Bluetooth利用可能時に既知UART Service限定スキャンを再開します。
    ///
    /// 責務: 現在の監視対象を1回のバックグラウンド互換BLEスキャンへ反映します。
    /// - Parameter central: スキャンを担当する中央マネージャー。
    private func restartScanIfAvailable(_ central: CBCentralManager) {
        guard preference != nil, !hasDeliveredArrival, central.state == .poweredOn else {
            return
        }
        if central.isScanning {
            central.stopScan()
        }
        central.scanForPeripherals(
            withServices: serviceUUIDs,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// Peripheral UUIDが現在の既定設定と一致するかを返します。
    ///
    /// 責務: 1件のCoreBluetooth Peripheralを保存済みシステム識別子と照合します。
    /// - Parameter peripheral: 照合対象のPeripheral。
    /// - Returns: 大文字小文字を無視したUUID文字列が一致する場合は `true`。
    private func matchesPreference(_ peripheral: CBPeripheral) -> Bool {
        guard let preference else { return false }
        return peripheral.identifier.uuidString.caseInsensitiveCompare(
            preference.systemIdentifier
        ) == .orderedSame
    }

    /// 既定Peripheralを接続確認に使用する終端として通知します。
    ///
    /// 責務: 現在の監視設定を重複のない1件のBLE接続終端通知へ変換します。
    /// - Parameter peripheral: 一致を確認した既定Peripheral。
    private func deliverArrival(for peripheral: CBPeripheral) {
        guard !hasDeliveredArrival,
              matchesPreference(peripheral),
              let preference,
              let arrival else {
            return
        }
        hasDeliveredArrival = true
        centralManager?.stopScan()
        arrival(
            OBDConnectionEndpoint(
                transport: .bluetoothLowEnergy,
                systemIdentifier: preference.systemIdentifier,
                displayName: preference.displayName
            )
        )
    }
}
#endif
