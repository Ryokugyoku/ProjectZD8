#if os(iOS) || os(macOS)
/// CoreBluetooth非依存のCharacteristic書き込み種別です。
nonisolated enum BLEWriteKind: Equatable, Sendable {
    /// 書き込み完了通知を受け取る応答あり書き込みです。
    case withResponse
    /// 完了通知のない応答なし書き込みです。
    case withoutResponse
}
#endif
