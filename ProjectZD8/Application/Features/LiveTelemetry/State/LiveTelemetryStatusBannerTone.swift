/// リアルタイム表示の状態バナーが表す調子です。
///
/// View はこの値を色へ対応させます(active=シアン、healthy=緑、warning=オレンジ)。
nonisolated enum LiveTelemetryStatusBannerTone: Equatable, Sendable {
    /// 探索など、進行中の処理を表します。
    case active
    /// 車両から応答を受信し続けている正常な状態を表します。
    case healthy
    /// 一時停止、停止中、失敗など注意が必要な状態を表します。
    case warning
}
