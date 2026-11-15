/// 一時停止中に起きたときに取る動作です。
nonisolated enum LiveTelemetryPauseWakeAction: Equatable, Sendable {
    /// 猶予を超えたため取得を終えます。
    case terminate
    /// 指定段階の回復を1回試し、成功したら取得を再開します。
    case attemptResume(AcquisitionRecoveryStage)
    /// 期限待ちが猶予内に返ったため、期限待ちをやり直します。
    case rearmDeadline
    /// 定期試行の待ちが試行時刻より前に返ったため、試行時刻までの待ちをやり直します。
    case rearmRetry
    /// 何もせず次の機会を待ちます。
    case keepWaiting
}
