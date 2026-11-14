/// 一時停止中に起きた理由と単調時計の現在値から、次の動作を決めます。
///
/// 猶予の判定を常に先に行います。猶予内(ちょうど3分を含む)なら、フォアグラウンド復帰とリンク復帰、
/// および定期試行の時刻への到達(`AcquisitionGracePeriodPolicy.retryIntervalNanoseconds` ごと)で回復を1回試します。
/// 待ちが早く返った場合は待ちをやり直し、遅く返った場合も単調時計の経過で判定します。
nonisolated struct LiveTelemetryPauseWakeEvaluator: Sendable {
    /// 状態を持たない判定を生成します。
    ///
    /// 責務: 一時停止中の起床判定を構築します。
    init() {}

    /// 起きた理由に対する次の動作を返します。
    ///
    /// 責務: 猶予切れを最優先し、次に起きた理由ごとの動作を選びます。
    /// - Parameters:
    ///   - reason: 待ちから起きた理由。
    ///   - window: 一時停止の開始時点。
    ///   - nowNanoseconds: 単調時計の現在値。
    ///   - cause: 一時停止に入った途切れの原因。
    /// - Returns: 次に取る動作。
    func action(
        for reason: LiveTelemetryPauseWakeReason,
        window: LiveTelemetryPauseWindow,
        nowNanoseconds: UInt64,
        cause: LiveTelemetryInterruptionCause
    ) -> LiveTelemetryPauseWakeAction {
        guard window.decision(nowNanoseconds: nowNanoseconds) == .continueWaiting else { return .terminate }
        switch reason {
        case .deadlineReached:
            return .rearmDeadline
        case .retryDue:
            return window.isRetryDue(nowNanoseconds: nowNanoseconds) ? .attemptResume(resumeStage(for: cause)) : .rearmRetry
        case .signal(.foregroundEntered), .signal(.linkRestored):
            return .attemptResume(resumeStage(for: cause))
        case .signal(.backgroundEntered), .signal(.linkLost):
            return .keepWaiting
        }
    }

    /// 一時停止中の復帰で試す回復段階を返します。
    ///
    /// 責務: リンク断なら再接続、応答途絶ならリンクを保ったままの `ATZ` 再初期化を選びます。
    /// - Parameter cause: 一時停止に入った途切れの原因。
    /// - Returns: 1回試す回復段階。
    func resumeStage(for cause: LiveTelemetryInterruptionCause) -> AcquisitionRecoveryStage {
        switch cause {
        case .linkLost: .reconnectLink
        case .responseStall: .reinitializeFromReset
        }
    }
}
