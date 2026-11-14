/// 件数や経過時間にかかわらず保存待ちの取得記録を保存させる契機です。
nonisolated enum LiveTelemetryAcquisitionFlushTrigger: String, Equatable, Sendable {
    /// 連続取得区間を閉じます。
    case segmentEnded
    /// 接続セッションの取得を終えます。
    case sessionEnded
    /// アプリがバックグラウンドへ移行しました。
    case backgroundTransition
}
