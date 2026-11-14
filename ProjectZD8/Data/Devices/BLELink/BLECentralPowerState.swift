#if os(iOS) || os(macOS)
/// CoreBluetooth非依存のBluetooth中央役の電源・利用可否状態です。
nonisolated enum BLECentralPowerState: Equatable, Sendable {
    /// 状態がまだ確定していません。
    case unknown
    /// システムとの接続が一時的に失われ、再確立を待っています。
    case resetting
    /// 実行環境がBluetooth Low Energy中央役に対応していません。
    case unsupported
    /// Bluetooth利用が許可されていません。
    case unauthorized
    /// Bluetoothが無効です。
    case poweredOff
    /// Bluetoothが有効で利用できます。
    case poweredOn
}
#endif
