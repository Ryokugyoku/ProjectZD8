/// リアルタイム表示への操作です。
nonisolated enum LiveTelemetryAction: Equatable, Sendable {
    /// 記録が終わった後に残っている値を消します。記録中は無視します。
    case clearRequested
}
