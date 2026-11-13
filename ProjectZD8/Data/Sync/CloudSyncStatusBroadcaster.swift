import Foundation
import Synchronization

/// 同期状態を保持し、変化を全ての購読者へ流します。どのスレッドからも呼べます。
nonisolated final class CloudSyncStatusBroadcaster: Sendable {
    private struct Storage {
        var tracker: CloudSyncStatusTracker
        var continuations: [UUID: AsyncStream<CloudSyncStatus>.Continuation] = [:]
    }

    private let storage: Mutex<Storage>

    /// 責務: 初期状態を指定して生成します。
    init(tracker: CloudSyncStatusTracker = CloudSyncStatusTracker()) {
        storage = Mutex(Storage(tracker: tracker))
    }

    /// 現在の同期状態です。
    var status: CloudSyncStatus {
        storage.withLock { $0.tracker.status }
    }

    /// 責務: 状態を更新し、変化していれば購読者へ流します。
    func update(_ change: (inout CloudSyncStatusTracker) -> Void) {
        // 順序を保つため、ロック内で流します(yield は待たずに戻ります)。
        storage.withLock { storage in
            let before = storage.tracker.status
            change(&storage.tracker)
            let after = storage.tracker.status
            guard before != after else { return }
            for continuation in storage.continuations.values { continuation.yield(after) }
        }
    }

    /// 責務: 現在の状態を最初に流し、以後の変化を流すストリームを返します。
    func stream() -> AsyncStream<CloudSyncStatus> {
        let (stream, continuation) = AsyncStream<CloudSyncStatus>.makeStream(bufferingPolicy: .bufferingNewest(8))
        let id = UUID()
        storage.withLock { storage in
            storage.continuations[id] = continuation
            continuation.yield(storage.tracker.status)
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.storage.withLock { $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }
}
