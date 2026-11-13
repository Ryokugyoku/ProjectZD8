import Foundation
@testable import ProjectZD8

/// 分析テスト用のクラウド同期です。復元の呼び出しを記録し、進捗を流して指定の結果を返します。
actor AnalysisFakeCloudSync: CloudSyncPort {
    private let sessions: AnalysisFakeSessionRepository
    private let failure: CloudSyncFailure?
    /// 復元を要求されたセッションです。
    private(set) var restored: [SessionID] = []

    /// 責務: 復元後にローカルへ戻す保管庫と、返す失敗(任意)を指定して生成します。
    init(sessions: AnalysisFakeSessionRepository, failure: CloudSyncFailure? = nil) {
        self.sessions = sessions
        self.failure = failure
    }

    func start() async {}
    nonisolated func statusUpdates() -> AsyncStream<CloudSyncStatus> { AsyncStream { $0.finish() } }
    func syncNow() async throws {}
    func eraseAllData() async throws {}

    func restoreSessionArchive(_ id: SessionID, progress: @escaping @Sendable (Double) -> Void) async throws {
        restored.append(id)
        progress(0.5)
        if let failure { throw failure }
        await sessions.markLocal(id)
        progress(1)
    }
}
