/// 接続セッション内で連続取得区間が始まった直接原因です。
nonisolated enum ConnectionSessionSegmentStartReason: String, Codable, Equatable, Sendable {
    /// セッション開始に伴う最初の区間です。
    case initial
    /// 通信境界の再接続後に取得を再開しました。
    case reconnected
    /// アプリプロセスの再起動後に取得を再開しました。
    case processRelaunched
    /// 取得モードの切替後に取得を再開しました。
    case modeSwitched
}
