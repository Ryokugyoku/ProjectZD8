/// 一時停止中に待ちから起きた理由です。
nonisolated enum LiveTelemetryPauseWakeReason: Equatable, Sendable {
    /// 取得ループの外から判定し直す機会が届きました。
    case signal(LiveTelemetryAcquisitionWakeSignal)
    /// 猶予切れの期限待ちが返りました。早く返った場合も含みます。
    case deadlineReached
}
