#if os(iOS) || os(macOS)
import Foundation

/// ペリフェラル役から届くイベントです。UUIDは大文字の文字列で表します。
nonisolated enum BLEPeripheralEvent: Equatable, Sendable {
    /// Service探索が完了しました。失敗時は `errorDescription` を持ちます。
    case didDiscoverServices(serviceUUIDs: [String], errorDescription: String?)
    /// 1件のServiceのCharacteristic探索が完了しました。失敗時は `errorDescription` を持ちます。
    case didDiscoverCharacteristics(
        serviceUUID: String,
        capabilities: [AppleBluetoothCharacteristicCapability],
        errorDescription: String?
    )
    /// CharacteristicのNotify状態が更新されました。
    case didUpdateNotificationState(characteristicUUID: String, isNotifying: Bool, errorDescription: String?)
    /// Characteristicの値を受信しました。
    case didReceiveValue(characteristicUUID: String, value: Data, errorDescription: String?)
    /// 応答あり書き込みが完了しました。
    case didWriteValue(characteristicUUID: String, errorDescription: String?)
    /// 応答なし書き込みを再び送信できるようになりました。
    case isReadyToSendWriteWithoutResponse
}
#endif
