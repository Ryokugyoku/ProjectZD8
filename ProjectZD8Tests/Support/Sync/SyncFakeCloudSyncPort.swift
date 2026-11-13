import Foundation
import Synchronization
@testable import ProjectZD8

/// 同期の振る舞いを指定できる `CloudSyncPort` の偽物です。
final class SyncFakeCloudSyncPort: CloudSyncPort, Sendable {
    private struct Storage {
        var continuation: AsyncStream<CloudSyncStatus>.Continuation?
        var syncNowError: CloudSyncFailure?
        var eraseError: CloudSyncFailure?
        var syncNowCount = 0
        var eraseCount = 0
        var statusSubscriptionCount = 0
    }

    private let storage = Mutex(Storage())

    /// 責務: 初期状態を流すストリームを用意した偽物を生成します。
    init(syncNowError: CloudSyncFailure? = nil, eraseError: CloudSyncFailure? = nil) {
        storage.withLock {
            $0.syncNowError = syncNowError
            $0.eraseError = eraseError
        }
    }

    /// 「今すぐ同期」が呼ばれた回数です。
    var syncNowCount: Int { storage.withLock { $0.syncNowCount } }
    /// 全データ削除が呼ばれた回数です。
    var eraseCount: Int { storage.withLock { $0.eraseCount } }
    /// 状態の購読が始まった回数です。
    var statusSubscriptionCount: Int { storage.withLock { $0.statusSubscriptionCount } }

    /// 責務: 購読者へ状態を流します。
    func emit(_ status: CloudSyncStatus) {
        let continuation = storage.withLock { $0.continuation }
        continuation?.yield(status)
    }

    func start() async {}

    func statusUpdates() -> AsyncStream<CloudSyncStatus> {
        let (stream, continuation) = AsyncStream<CloudSyncStatus>.makeStream()
        storage.withLock {
            $0.continuation = continuation
            $0.statusSubscriptionCount += 1
        }
        continuation.yield(.idle(lastSyncedAt: nil))
        return stream
    }

    func syncNow() async throws {
        let error = storage.withLock { storage -> CloudSyncFailure? in
            storage.syncNowCount += 1
            return storage.syncNowError
        }
        if let error { throw error }
    }

    func restoreSessionArchive(_ id: SessionID, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
    }

    func eraseAllData() async throws {
        let error = storage.withLock { storage -> CloudSyncFailure? in
            storage.eraseCount += 1
            return storage.eraseError
        }
        if let error { throw error }
    }
}
