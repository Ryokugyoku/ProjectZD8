/// 記録ポートのスパイに失敗させる呼び出しです。
enum LiveTelemetryRecordingFailurePoint: Equatable, Sendable {
    /// `start` を失敗させます。
    case start
    /// `beginRound` を失敗させます。
    case beginRound
    /// `record` を失敗させます。
    case record
    /// `finishRound` を失敗させます。
    case finishRound
    /// `flush` を失敗させます。
    case flush
    /// `endSegment` を失敗させます。
    case endSegment
    /// `beginSegment` を失敗させます。
    case beginSegment
    /// `finish` を失敗させます。
    case finish
}
