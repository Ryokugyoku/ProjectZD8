#if os(iOS) || os(macOS)
/// Bluetooth中央役から届くイベントです。
@MainActor
enum BLECentralEvent {
    /// 電源・利用可否状態が更新されました。
    case powerStateDidUpdate(BLECentralPowerState)
    /// 状態復元でOSが保持していたペリフェラル一覧が渡されました。
    case willRestore([any BLEPeripheralRole])
    /// スキャンでペリフェラルを発見しました。
    case didDiscover(any BLEPeripheralRole)
    /// ペリフェラルへの接続が成功しました。
    case didConnect(any BLEPeripheralRole)
    /// ペリフェラルへの接続が失敗しました。OSのエラー説明を保持します。
    case didFailToConnect(any BLEPeripheralRole, errorDescription: String?)
    /// ペリフェラルとの接続が切れました。OSのエラー説明を保持します(自発的キャンセルでは `nil` のことがあります)。
    case didDisconnect(any BLEPeripheralRole, errorDescription: String?)
}
#endif
