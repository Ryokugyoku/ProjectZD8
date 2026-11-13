import XCTest
@testable import ProjectZD8

/// 同期状態の配信を確認します。
final class CloudSyncStatusBroadcasterTests: XCTestCase {
    /// 責務: 購読開始時に現在の状態を流し、変化した時だけ流すことを確認します。
    func testStreamYieldsCurrentThenChangesOnly() async {
        let broadcaster = CloudSyncStatusBroadcaster()
        var iterator = broadcaster.stream().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial, .unavailable(.temporarilyUnavailable))

        broadcaster.update { $0.accountChanged(unavailableReason: .temporarilyUnavailable) } // 変化なし
        broadcaster.update { $0.accountChanged(unavailableReason: nil) }
        broadcaster.update { $0.operationStarted() }
        let first = await iterator.next()
        let second = await iterator.next()
        XCTAssertEqual(first, .idle(lastSyncedAt: nil))
        XCTAssertEqual(second, .syncing)
        XCTAssertEqual(broadcaster.status, .syncing)
    }
}
