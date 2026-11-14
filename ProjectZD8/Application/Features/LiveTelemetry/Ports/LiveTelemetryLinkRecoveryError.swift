/// 回復操作を完了できなかった理由です。
nonisolated enum LiveTelemetryLinkRecoveryError: Error, Equatable, Sendable {
    /// 回復に使えるリンク(開いているトランスポート)がありません。
    case linkUnavailable
    /// 応答待ちの上限までにプロンプトが返りませんでした。
    case timedOut
    /// アダプターが初期化コマンドを拒否しました。
    case rejected
}
