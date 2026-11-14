#if os(iOS) || os(macOS)
import Foundation

/// Bluetooth中央役を具象CoreBluetooth型なしで表す境界です。テストはこのプロトコルのフェイクを注入します。
@MainActor
protocol BLECentralRole: AnyObject {
    /// 現在の電源・利用可否状態です。
    var powerState: BLECentralPowerState { get }

    /// 中央役イベントの通知先です。
    var eventHandler: (@MainActor (BLECentralEvent) -> Void)? { get set }

    /// OSが既に知っているペリフェラルを識別子から取得します。
    ///
    /// 責務: 識別子一覧をOSが保持するペリフェラル役一覧へ解決します。
    /// - Parameter identifiers: 取得するペリフェラル識別子。
    /// - Returns: 取得できたペリフェラル役。見つからなければ空配列。
    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [any BLEPeripheralRole]

    /// 指定Serviceを広告するペリフェラルのスキャンを開始します。
    ///
    /// 責務: Service UUID一覧に限定したスキャンを開始します。
    /// - Parameter serviceUUIDs: 対象Service UUID文字列。
    func scanForPeripherals(withServices serviceUUIDs: [String])

    /// 進行中のスキャンを停止します。
    ///
    /// 責務: スキャンを停止します。
    func stopScan()

    /// ペリフェラルへタイムアウトなしの保留接続要求を出します。
    ///
    /// 責務: 1件のペリフェラルへOSの保留接続要求を出します。
    /// - Parameter peripheral: 接続対象。
    func connect(_ peripheral: any BLEPeripheralRole)

    /// ペリフェラルとの接続または保留中の接続要求をキャンセルします。
    ///
    /// 責務: 1件のペリフェラルの接続をキャンセルします。
    /// - Parameter peripheral: キャンセル対象。
    func cancelConnection(_ peripheral: any BLEPeripheralRole)
}
#endif
