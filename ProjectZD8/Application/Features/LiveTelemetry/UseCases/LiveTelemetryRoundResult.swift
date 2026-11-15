/// 1周回を送った結果です。
nonisolated enum LiveTelemetryRoundResult: Equatable, Sendable {
    /// 周回の全要求を送り終えました。
    case completed(LiveTelemetryRoundOutcome)
    /// 周回の途中で取得が途切れました。残りの要求は送っていません。
    case interrupted(LiveTelemetryInterruptionCause)
}
