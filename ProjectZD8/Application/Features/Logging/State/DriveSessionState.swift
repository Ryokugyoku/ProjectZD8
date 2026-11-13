/// 記録の流れ全体の表示状態です。
nonisolated struct DriveSessionState: Equatable, Sendable {
    /// 現在の段階です。
    var phase: DriveSessionPhase = .idle
    /// 直近の失敗です。`failureDismissed` か次の接続開始で消えます。
    var failure: DriveSessionFailure?
    /// 接続中または記録中のアダプターです。`idle` では `nil` です。
    var adapter: AdapterDescriptor?
    /// 記録中のセッション要約です。記録中以外は `nil` です。
    var activeSession: ActiveSessionSummary?
    /// 直近に終了したセッションです。ユーザー停止以外の終了理由もここで確認できます。次の接続開始で消えます。
    var lastEndedSession: DriveSession?
    /// 今回の起動時に閉じた、前回の未終了セッション数です。
    var recoveredSessionCount = 0

    /// 責務: 初期状態を生成します。
    init() {}
}
