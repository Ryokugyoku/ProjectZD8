/// 取得ループの外から届く、状態を判定し直す機会です。
nonisolated enum LiveTelemetryAcquisitionWakeSignal: Equatable, Sendable {
    /// アプリがフォアグラウンドへ戻りました。
    case foregroundEntered
    /// アプリがバックグラウンドへ移りました。
    case backgroundEntered
    /// アダプターとのリンクが送受信できる状態へ戻りました。
    case linkRestored
    /// アダプターとのリンクが切れました。
    case linkLost
}
