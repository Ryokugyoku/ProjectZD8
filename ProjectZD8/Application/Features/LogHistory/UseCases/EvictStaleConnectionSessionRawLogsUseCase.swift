import Foundation

/// 3日以上閲覧されていないCloudKit保存済みRawログを端末から退避します。
struct EvictStaleConnectionSessionRawLogsUseCase {
    /// 退避可否を判定する保持方針です。
    private let policy: ConnectionSessionRawCacheRetentionPolicy
    /// セッション一覧の取得先です。
    private let sessionRepository: any ConnectionSessionRepository
    /// Rawログのローカル保存先です。
    private let rawLogRepository: any ConnectionSessionRawLogRepository
    /// 判定基準日時を生成するクロックです。
    private let now: () -> Date

    /// 保持方針、保存先、クロックを固定して生成します。
    ///
    /// 責務: Rawキャッシュ保持判断をローカルRaw除去操作へ結び付けます。
    /// - Parameters:
    ///   - policy: CloudKit保護と最終閲覧日時を評価する保持方針。
    ///   - sessionRepository: アカウント単位のセッション取得先。
    ///   - rawLogRepository: Rawログのローカル保存先。
    ///   - now: 判定基準日時を生成するクロック。
    init(
        policy: ConnectionSessionRawCacheRetentionPolicy = .init(),
        sessionRepository: any ConnectionSessionRepository,
        rawLogRepository: any ConnectionSessionRawLogRepository,
        now: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.sessionRepository = sessionRepository
        self.rawLogRepository = rawLogRepository
        self.now = now
    }

    /// 指定アカウントの期限切れRawキャッシュを退避します。
    ///
    /// 責務: 1件のアカウントスコープを保持期限切れRawログのローカル除去結果へ変換します。
    /// - Parameter accountIdentifier: 退避対象を所有するAppleアカウント識別子。
    /// - Throws: 履歴取得またはローカルRaw除去に失敗した場合のエラー。
    func execute(accountIdentifier: String) throws {
        let referenceDate = now()
        for session in try sessionRepository.sessions(for: accountIdentifier)
        where policy.shouldEvict(session, at: referenceDate) {
            try rawLogRepository.removeLocalEntries(for: session.id)
        }
    }
}
