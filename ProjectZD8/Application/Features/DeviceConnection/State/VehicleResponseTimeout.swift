/// 車両のECU応答を待つ時間の指定です。
nonisolated enum VehicleResponseTimeout: Equatable, Sendable {
    /// アダプターの通常のタイムアウトで1回確認します。初期化直後の最初の確認で使います。
    case standard

    /// アダプター側で設定できる最大のタイムアウトで確認します。無応答の間の再確認で使います。
    case adapterMaximum

    /// 抑止中の見張りで確認します。アダプターの適応タイミングを切って(`ATAT0`)最大のタイムアウトで送り、
    /// ECU が応答してもタイムアウト満了まで待たせることで、応答の受信を起点にしても約1秒周期にします(実アダプターでは未検証)。
    case heldWatch
}
