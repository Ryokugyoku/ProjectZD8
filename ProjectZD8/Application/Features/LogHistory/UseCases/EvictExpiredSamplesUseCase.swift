import Foundation

/// 保持期間を過ぎた、iCloud保存済みセッションのRawをこの端末から解放します。
nonisolated struct EvictExpiredSamplesUseCase: Sendable {
    /// 実行結果です。
    struct Result: Equatable, Sendable {
        /// 解放したセッションです。
        let evicted: [SessionID]
        /// 解放できなかったセッションです。
        let failed: [SessionID]
    }

    private let sessions: any SessionRepository
    private let settings: any AppSettingsStorePort
    private let now: @Sendable () -> Date

    /// 責務: 解放に使う永続化契約・設定・時計を固定します。
    init(sessions: any SessionRepository, settings: any AppSettingsStorePort, now: @escaping @Sendable () -> Date = Date.init) {
        self.sessions = sessions
        self.settings = settings
        self.now = now
    }

    /// 期限切れのRawを解放します。
    ///
    /// 責務: 終了日時から保持期間(`AppSettings.localRawRetention`)を超えて経った、終了済み・アップロード済み・この端末にRawがあるセッションだけを解放します。保持期間ちょうどは対象外で、無期限なら何もしません。
    /// - Returns: 解放できたセッションと、解放に失敗したセッション。
    /// - Throws: セッション一覧を読み込めない場合の永続化エラー。
    func execute() async throws -> Result {
        guard let days = settings.load().localRawRetention.days else { return Result(evicted: [], failed: []) }
        let threshold = TimeInterval(days) * 86_400
        let current = now()
        var evicted: [SessionID] = []
        var failed: [SessionID] = []
        for session in try await sessions.sessions(for: nil) {
            guard let endedAt = session.endedAt,
                  session.archiveDigest != nil,
                  session.rawAvailability == .local,
                  current.timeIntervalSince(endedAt) > threshold else { continue }
            do {
                try await sessions.evictSamples(for: session.id)
                evicted.append(session.id)
            } catch {
                failed.append(session.id)
            }
        }
        return Result(evicted: evicted, failed: failed)
    }
}
