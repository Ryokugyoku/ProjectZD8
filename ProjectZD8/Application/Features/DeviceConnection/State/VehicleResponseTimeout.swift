/// 車両のECU応答を待つ時間の指定です。
nonisolated enum VehicleResponseTimeout: Equatable, Sendable {
    /// アダプターの通常のタイムアウトで1回確認します。初期化直後の最初の確認で使います。
    case standard

    /// アダプター側で設定できる最大のタイムアウトで確認します。低頻度の再確認で使います。
    case adapterMaximum
}
