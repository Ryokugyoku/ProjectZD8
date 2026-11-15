/// 応答駆動の取得ループの現在の段階です。
nonisolated enum LiveTelemetryAcquisitionPhase: Equatable, Sendable {
    /// 要求を送り、応答を受けて記録しています。
    case acquiring
    /// 取得が途切れ、回復段階を試しています。
    /// - Parameters:
    ///   - cause: 途切れの原因。
    ///   - stage: 試している回復段階。
    ///   - attempt: その段階の1始まりの試行番号。
    case recovering(cause: LiveTelemetryInterruptionCause, stage: AcquisitionRecoveryStage, attempt: Int)
    /// 回復段階を使い切り、猶予内の復帰を待っています。
    case paused(cause: LiveTelemetryInterruptionCause)
}
