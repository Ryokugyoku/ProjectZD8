#if os(iOS) || os(macOS)
/// CoreBluetooth非依存のペリフェラル接続状態です。
nonisolated enum BLEPeripheralConnectionState: Equatable, Sendable {
    /// 接続していません。
    case disconnected
    /// 接続要求を出しています。
    case connecting
    /// 接続済みです。
    case connected
    /// 切断処理中です。
    case disconnecting
}
#endif
