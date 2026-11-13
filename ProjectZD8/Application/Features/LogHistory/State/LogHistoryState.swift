/// ログ履歴画面が描画する状態です。
nonisolated struct LogHistoryState: Equatable, Sendable {
    /// 読み込み段階です。
    enum LoadPhase: Equatable, Sendable {
        case idle
        case loading
        case loaded
    }

    var loadPhase: LoadPhase = .idle
    /// 現在記録中のセッションです(絞り込み・並び替えの対象外)。
    var activeSessions: [LogHistorySessionRow] = []
    /// 終了済みセッションを車両ごとにまとめ、絞り込みと並び順を適用したものです。最新のグループが先頭です。
    var groups: [LogHistoryVehicleGroup] = []
    var filter = LogHistoryFilter()
    var sortOrder: LogHistorySortOrder = .newest
    /// 絞り込み前の終了済みセッション件数です。
    var totalFinishedCount = 0
    /// 開いているセッション詳細です。
    var detail: LogHistorySessionDetail?
    /// 削除の確認待ちの内容です。
    var pendingDeletion: LogHistorySessionPrompt?
    /// 「この端末の領域を解放」の確認待ちの内容です。
    var pendingFreeUp: LogHistorySessionPrompt?
    /// ユーザーが分析を求めたセッションです。シェルが分析画面を開いたら `analysisRequestHandled` で消します。
    var analysisRequest: SessionID?
    /// 直近の失敗です。`failureDismissed` で消えます。
    var failure: LogHistoryFailure?

    /// 絞り込み後に表示するセッション件数です。
    var visibleCount: Int { groups.reduce(0) { $0 + $1.sessionCount } }
    /// 絞り込み条件が有効かどうかです。
    var hasActiveFilters: Bool { filter.isActive }
    /// 絞り込みの結果、終了済みセッションが1件も残らなかったかどうかです。
    var isFilteredEmpty: Bool { totalFinishedCount > 0 && groups.isEmpty }
}
