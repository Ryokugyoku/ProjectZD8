#if os(iOS) || os(macOS)
import Foundation

/// BLEペリフェラルを具象CoreBluetooth型なしで表す境界です。ServiceとCharacteristicは大文字UUID文字列で指定します。
@MainActor
protocol BLEPeripheralRole: AnyObject {
    /// OSがペリフェラルへ割り当てた識別子です。
    var identifier: UUID { get }

    /// 現在の接続状態です。
    var connectionState: BLEPeripheralConnectionState { get }

    /// 応答なし書き込みを今すぐ送信できるかどうかです。
    var canSendWriteWithoutResponse: Bool { get }

    /// ペリフェラル役イベントの通知先です。
    var eventHandler: (@MainActor (BLEPeripheralEvent) -> Void)? { get set }

    /// Service探索を開始します。
    ///
    /// 責務: 指定Serviceに限定したService探索を要求します。
    /// - Parameter serviceUUIDs: 探索するService UUID。`nil` は全Service。
    func discoverServices(_ serviceUUIDs: [String]?)

    /// 1件のServiceのCharacteristic探索を開始します。
    ///
    /// 責務: 発見済みServiceのCharacteristic探索を要求します。
    /// - Parameter serviceUUID: 対象Service UUID。
    func discoverCharacteristics(forService serviceUUID: String)

    /// CharacteristicのNotifyを有効化または無効化します。
    ///
    /// 責務: 1件のCharacteristicのNotify状態変更を要求します。
    /// - Parameters:
    ///   - enabled: 有効化する場合は `true`。
    ///   - characteristicUUID: 対象Characteristic UUID。
    ///   - serviceUUID: Characteristicを持つService UUID。
    func setNotifyValue(_ enabled: Bool, characteristicUUID: String, serviceUUID: String)

    /// 書き込み種別ごとの1回の最大書き込み長を返します。
    ///
    /// 責務: 書き込み種別に対応するOSの最大書き込みバイト数を返します。
    /// - Parameter kind: 書き込み種別。
    /// - Returns: 1回で書き込める最大バイト数。
    func maximumWriteValueLength(for kind: BLEWriteKind) -> Int

    /// Characteristicへ1チャンクを書き込みます。
    ///
    /// 責務: 1件のバイト列を指定種別でCharacteristicへ書き込みます。
    /// - Parameters:
    ///   - data: 書き込むバイト列(最大書き込み長以内)。
    ///   - characteristicUUID: 対象Characteristic UUID。
    ///   - serviceUUID: Characteristicを持つService UUID。
    ///   - kind: 書き込み種別。
    func writeValue(_ data: Data, characteristicUUID: String, serviceUUID: String, kind: BLEWriteKind)
}
#endif
