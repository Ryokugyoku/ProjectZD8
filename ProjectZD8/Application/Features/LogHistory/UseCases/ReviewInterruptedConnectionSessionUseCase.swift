/// ユーザーが意図した停止を元の終了理由を保ったまま正式データとして保存します。
struct ReviewInterruptedConnectionSessionUseCase {
    /// 確認結果を保存する接続セッション境界です。
    private let repository: any ConnectionSessionRepository

    /// 接続セッション保存先を固定して生成します。
    ///
    /// 責務: 1件の接続セッション保存先を中断確認ワークフローへ結び付けます。
    /// - Parameter repository: 確認結果を保存する接続セッション境界。
    init(repository: any ConnectionSessionRepository) {
        self.repository = repository
    }

    /// 応答停止または接続喪失をユーザー操作による停止として確認します。
    ///
    /// 責務: 1件の確認可能な終了済みセッションへユーザー操作停止の確認結果を保存します。
    /// - Parameter session: 確認対象の接続セッション。
    /// - Returns: 確認結果を反映した接続セッション。
    /// - Throws: 対象が確認不能な状態、または永続化に失敗した場合のエラー。
    func execute(session: ConnectionSession) throws -> ConnectionSession {
        guard session.endedAt != nil, session.needsStopReview else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        var reviewed = session
        reviewed.stopReviewDecision = .userInitiated
        try repository.save(reviewed)
        return reviewed
    }
}
