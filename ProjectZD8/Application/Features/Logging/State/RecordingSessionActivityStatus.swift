/// 記録中表示の状態欄(文言キーと強調)です。
nonisolated struct RecordingSessionActivityStatus: Equatable, Sendable {
    /// 取得開始前の待機段階、または通常終了した状態のキーです。
    static let endedKey = "live_activity.status.ended"
    /// 対応PIDを探索している段階のキーです。
    static let readingKey = "live_activity.status.reading"
    /// 継続取得している段階のキーです。
    static let recordingKey = "live_activity.status.recording"
    /// 一時停止中で原因を特定できない場合のキーです。
    static let pausedKey = "live_activity.status.paused"
    /// 停止処理中の段階のキーです。
    static let stoppingKey = "live_activity.status.stopping"
    /// 取得に失敗した段階のキーです。
    static let failedKey = "live_activity.status.failed"

    /// 状態を表すローカライズキーです。
    let key: String
    /// 状態欄の強調です。
    let tone: RecordingSessionActivityStatusTone

    /// 取得状態から状態欄を生成します。
    ///
    /// 責務: 取得段階ごとに文言キーと強調を決めます。一時停止は原因別のキー、
    /// 待機段階は失敗キー(猶予切れ等)があれば警告、無ければ通常終了とします。
    /// - Parameter telemetry: PID継続取得の現在状態。
    @MainActor
    init(telemetry: LiveTelemetryState) {
        switch telemetry.phase {
        case .idle:
            if let failureKey = telemetry.failureKey {
                (key, tone) = (failureKey, .warning)
            } else {
                (key, tone) = (Self.endedKey, .normal)
            }
        case .reading:
            (key, tone) = (Self.readingKey, .normal)
        case .loaded:
            (key, tone) = (Self.recordingKey, .normal)
        case .paused:
            (key, tone) = (telemetry.pauseStatus?.statusKey ?? Self.pausedKey, .warning)
        case .stopping:
            (key, tone) = (Self.stoppingKey, .normal)
        case .failed:
            (key, tone) = (Self.failedKey, .warning)
        }
    }
}
