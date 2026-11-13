/// ログ履歴画面からモデルへ送る操作です。
nonisolated enum LogHistoryAction: Sendable {
    /// 読み込みを始め、以後の変更通知を購読します。
    case started
    /// 変更通知の購読を止めます。
    case stopped
    /// 再読み込みします。
    case refreshRequested
    /// 絞り込み条件を変更します。
    case filterChanged(LogHistoryFilter)
    /// 絞り込み条件を解除します。
    case filterReset
    /// 並び順を変更します。
    case sortOrderChanged(LogHistorySortOrder)
    /// セッション詳細を開きます。
    case detailRequested(SessionID)
    /// セッション詳細を閉じます。
    case detailClosed
    /// セッション削除の確認を求めます(記録中は失敗になります)。
    case deleteRequested(SessionID)
    /// 確認済みの削除を実行します。
    case deleteConfirmed
    /// 削除をやめます。
    case deleteCancelled
    /// 「この端末の領域を解放」の確認を求めます(アップロード済みの終了済みセッションのみ)。
    case freeUpSpaceRequested(SessionID)
    /// 確認済みの領域解放を実行します。
    case freeUpSpaceConfirmed
    /// 領域解放をやめます。
    case freeUpSpaceCancelled
    /// セッションの分析を求めます。`analysisRequest` に反映されます。
    case analysisRequested(SessionID)
    /// 分析画面を開き終えたことを伝え、`analysisRequest` を消します。
    case analysisRequestHandled
    /// 表示中の失敗を閉じます。
    case failureDismissed
}
