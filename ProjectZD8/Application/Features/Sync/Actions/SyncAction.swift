/// 同期画面から送る操作です。
nonisolated enum SyncAction: Equatable, Sendable {
    /// 画面が表示された。同期状態の購読を始めます。
    case appeared
    /// 「今すぐ同期」が押された。
    case syncNowTapped
    /// 全データ削除が要求された。確認を表示します。
    case eraseAllRequested
    /// 全データ削除の確認で実行が選ばれた。
    case eraseAllConfirmed
    /// 全データ削除の確認が取り消された。
    case eraseAllCancelled
    /// 表示中の失敗(または完了)の通知が閉じられた。
    case failureDismissed
}
