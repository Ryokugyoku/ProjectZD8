import Foundation
import Synchronization
@testable import ProjectZD8

/// 変更通知を手動で発火できるテスト用の `StoreChangeObserving` です。
final class RecordsFakeStoreChanges: StoreChangeObserving, Sendable {
    private let state = Mutex(State())

    private struct State {
        var continuations: [AsyncStream<Void>.Continuation] = []
        var requestedAreas: [Set<StoreArea>] = []
    }

    /// 購読時に要求された領域の履歴です。
    var requestedAreas: [Set<StoreArea>] { state.withLock { $0.requestedAreas } }

    func changes(in areas: Set<StoreArea>) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        state.withLock {
            $0.continuations.append(continuation)
            $0.requestedAreas.append(areas)
        }
        return stream
    }

    /// 全購読者へ変更を通知します。
    func emit() {
        state.withLock { $0.continuations }.forEach { $0.yield() }
    }
}
