/// 現在端末内のセッションRawログだけを除去します。
struct ReleaseConnectionSessionRawCacheUseCase {
    /// ローカル除去前の安全判断方針です。
    private let policy: ConnectionSessionLocalRemovalPolicy
    /// Rawログのローカル保存先です。
    private let repository: any ConnectionSessionRawLogRepository

    /// 除去方針とRawログ保存先を固定して生成します。
    ///
    /// 責務: 現在端末のローカル除去判断をRawログ保存先へ結び付けます。
    /// - Parameters:
    ///   - policy: CloudKit保管証跡を評価する除去方針。
    ///   - repository: Rawログのローカル保存先。
    init(
        policy: ConnectionSessionLocalRemovalPolicy = .init(),
        repository: any ConnectionSessionRawLogRepository
    ) {
        self.policy = policy
        self.repository = repository
    }

    /// 指定セッションのローカル除去前判断を返します。
    ///
    /// 責務: 1件の接続セッションを標準確認、データ消失警告、利用不能へ分類します。
    /// - Parameter session: 現在端末からRawログを除去する候補セッション。
    /// - Returns: CloudKit保管証跡を含む現在状態に対応した除去判断。
    func decision(for session: ConnectionSession) -> ConnectionSessionLocalRemovalDecision {
        policy.decision(for: session)
    }

    /// ユーザー確認済みセッションのRawログを現在端末から除去します。
    ///
    /// 責務: 1件の除去可能な終了済みセッションからローカルRawログだけを削除します。
    /// - Parameter session: ユーザーが除去を確定した接続セッション。
    /// - Throws: 現在状態で除去不能または保存先更新に失敗した場合のエラー。
    func execute(session: ConnectionSession) throws {
        guard policy.decision(for: session) != .unavailable else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        try repository.removeLocalEntries(for: session.id)
    }
}
