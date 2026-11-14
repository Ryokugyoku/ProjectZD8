#if os(iOS) || os(macOS)
import CoreBluetooth
import Foundation

/// 1つの `CBCentralManager` を `BLECentralRole` として包む薄いアダプターです。判断ロジックを持ちません。
@MainActor
final class AppleCoreBluetoothCentralRole: NSObject, BLECentralRole, CBCentralManagerDelegate {
    /// CoreBluetooth状態復元に使用する安定識別子です。
    static let restorationIdentifier = "ProjectZD8.adapter-link"

    /// このアダプターが生成した唯一の中央マネージャーです。
    private var centralManager: CBCentralManager!

    /// ペリフェラル識別子ごとのラッパーです。接続保留中に解放されないよう強参照で保持します。
    private var wrappers: [UUID: AppleCoreBluetoothPeripheralRole] = [:]

    /// 通知先の設定前に届いた状態復元ペリフェラルです。通知先が設定された時点で一度だけ届けます。
    private var undeliveredRestoredPeripherals: [any BLEPeripheralRole]?

    /// 中央役イベントの通知先です。設定時に未配送の状態復元イベントがあれば届けます。
    var eventHandler: (@MainActor (BLECentralEvent) -> Void)? {
        didSet { deliverUndeliveredRestorationIfPossible() }
    }

    /// 状態復元識別子付きの中央マネージャーを1つ生成します。
    ///
    /// 責務: メインキューで動く状態復元対応の `CBCentralManager` をこのアダプターに固定します。
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main, options: Self.managerOptions())
    }

    /// 現在の電源・利用可否状態です。
    var powerState: BLECentralPowerState {
        switch centralManager.state {
        case .unknown: .unknown
        case .resetting: .resetting
        case .unsupported: .unsupported
        case .unauthorized: .unauthorized
        case .poweredOff: .poweredOff
        case .poweredOn: .poweredOn
        @unknown default: .unknown
        }
    }

    /// 識別子からOSが知っているペリフェラルを取得します。
    ///
    /// 責務: `retrievePeripherals(withIdentifiers:)` の結果をラッパーへ変換します。
    /// - Parameter identifiers: 取得する識別子。
    /// - Returns: 取得できたペリフェラル役。
    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [any BLEPeripheralRole] {
        centralManager.retrievePeripherals(withIdentifiers: identifiers).map(wrapper(for:))
    }

    /// Service限定スキャンを開始します。
    ///
    /// 責務: UUID文字列を `CBUUID` へ変換して重複通知なしのスキャンを開始します。
    /// - Parameter serviceUUIDs: 対象Service UUID文字列。
    func scanForPeripherals(withServices serviceUUIDs: [String]) {
        centralManager.scanForPeripherals(
            withServices: serviceUUIDs.map { CBUUID(string: $0) },
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// スキャンを停止します。
    ///
    /// 責務: `stopScan()` を呼びます。
    func stopScan() {
        centralManager.stopScan()
    }

    /// タイムアウトなしの保留接続要求を出します。
    ///
    /// 責務: このアダプターが生成したラッパーだけを `connect(_:options:)` へ渡します。
    /// - Parameter peripheral: 接続対象。
    func connect(_ peripheral: any BLEPeripheralRole) {
        guard let wrapped = peripheral as? AppleCoreBluetoothPeripheralRole else { return }
        centralManager.connect(wrapped.peripheral, options: nil)
    }

    /// 接続または保留中の接続要求をキャンセルします。
    ///
    /// 責務: このアダプターが生成したラッパーだけを `cancelPeripheralConnection(_:)` へ渡します。
    /// - Parameter peripheral: キャンセル対象。
    func cancelConnection(_ peripheral: any BLEPeripheralRole) {
        guard let wrapped = peripheral as? AppleCoreBluetoothPeripheralRole else { return }
        centralManager.cancelPeripheralConnection(wrapped.peripheral)
    }

    /// 状態更新をイベントへ変換します。
    ///
    /// 責務: `centralManagerDidUpdateState` を電源状態イベントへ変換します。
    /// - Parameter central: 状態が更新された中央マネージャー。
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        eventHandler?(.powerStateDidUpdate(powerState))
    }

    /// 状態復元をイベントへ変換します。
    ///
    /// 責務: 復元辞書のペリフェラル一覧をラッパーへ変換し、通知先がなければ設定時まで保持します。
    /// - Parameters:
    ///   - central: 復元された中央マネージャー。
    ///   - dict: OSが保存していた状態辞書。
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []).map(wrapper(for:))
        if let eventHandler {
            eventHandler(.willRestore(restored))
        } else {
            undeliveredRestoredPeripherals = restored
        }
    }

    /// 発見をイベントへ変換します。
    ///
    /// 責務: `didDiscover` をラッパーの発見イベントへ変換します。
    /// - Parameters:
    ///   - central: 中央マネージャー。
    ///   - peripheral: 発見したペリフェラル。
    ///   - advertisementData: 使用しない広告値。
    ///   - RSSI: 使用しない受信強度。
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        eventHandler?(.didDiscover(wrapper(for: peripheral)))
    }

    /// 接続成功をイベントへ変換します。
    ///
    /// 責務: `didConnect` を接続成功イベントへ変換します。
    /// - Parameters:
    ///   - central: 中央マネージャー。
    ///   - peripheral: 接続したペリフェラル。
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        eventHandler?(.didConnect(wrapper(for: peripheral)))
    }

    /// 接続失敗をイベントへ変換します。
    ///
    /// 責務: `didFailToConnect` を接続失敗イベントへ変換します。
    /// - Parameters:
    ///   - central: 中央マネージャー。
    ///   - peripheral: 接続に失敗したペリフェラル。
    ///   - error: OSのエラー。
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        eventHandler?(.didFailToConnect(wrapper(for: peripheral), errorDescription: error?.localizedDescription))
    }

    /// 切断をイベントへ変換します。
    ///
    /// 責務: `didDisconnectPeripheral` を切断イベントへ変換します。
    /// - Parameters:
    ///   - central: 中央マネージャー。
    ///   - peripheral: 切断したペリフェラル。
    ///   - error: OSのエラー。
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        eventHandler?(.didDisconnect(wrapper(for: peripheral), errorDescription: error?.localizedDescription))
    }

    /// 同じ `CBPeripheral` に対して常に同じラッパーを返します。
    ///
    /// 責務: ペリフェラル識別子ごとにラッパーを1つ保持し、同じオブジェクトなら再利用します。
    /// - Parameter peripheral: 包むペリフェラル。
    /// - Returns: 保持しているラッパー。
    private func wrapper(for peripheral: CBPeripheral) -> AppleCoreBluetoothPeripheralRole {
        if let existing = wrappers[peripheral.identifier], existing.peripheral === peripheral {
            return existing
        }
        let created = AppleCoreBluetoothPeripheralRole(peripheral: peripheral)
        wrappers[peripheral.identifier] = created
        return created
    }

    /// 通知先の設定前に届いた状態復元イベントを一度だけ届けます。
    ///
    /// 責務: 保持していた状態復元ペリフェラルを新しい通知先へ渡して破棄します。
    private func deliverUndeliveredRestorationIfPossible() {
        guard let eventHandler, let restored = undeliveredRestoredPeripherals else { return }
        undeliveredRestoredPeripherals = nil
        eventHandler(.willRestore(restored))
    }

    /// 中央マネージャーの生成オプションを返します。
    ///
    /// 責務: 電源アラートを出さず、状態復元はバックグラウンドBluetoothを持つiOSだけで有効にします。
    /// - Returns: `CBCentralManager` の生成オプション。
    private static func managerOptions() -> [String: Any] {
        var options: [String: Any] = [CBCentralManagerOptionShowPowerAlertKey: false]
        #if os(iOS)
        options[CBCentralManagerOptionRestoreIdentifierKey] = restorationIdentifier
        #endif
        return options
    }
}
#endif
