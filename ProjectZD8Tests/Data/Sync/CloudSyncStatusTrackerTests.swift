import XCTest
@testable import ProjectZD8

/// 同期状態の導出を確認します。
final class CloudSyncStatusTrackerTests: XCTestCase {
    /// 責務: 利用不可・送受信中・失敗・待機の優先順位と、成功で失敗が消えることを確認します。
    func testStatusTransitions() {
        var tracker = CloudSyncStatusTracker()
        XCTAssertEqual(tracker.status, .unavailable(.temporarilyUnavailable))

        tracker.accountChanged(unavailableReason: nil)
        XCTAssertEqual(tracker.status, .idle(lastSyncedAt: nil))

        tracker.operationStarted()
        tracker.operationStarted()
        XCTAssertEqual(tracker.status, .syncing)
        tracker.operationFinished(at: Date(timeIntervalSince1970: 10), failure: .network)
        XCTAssertEqual(tracker.status, .syncing)
        tracker.operationFinished(at: Date(timeIntervalSince1970: 11), failure: .network)
        XCTAssertEqual(tracker.status, .failed(.network))

        tracker.operationStarted()
        tracker.operationFinished(at: Date(timeIntervalSince1970: 20), failure: nil)
        XCTAssertEqual(tracker.status, .idle(lastSyncedAt: Date(timeIntervalSince1970: 20)))

        tracker.recordFailure(.quotaExceeded)
        XCTAssertEqual(tracker.status, .failed(.quotaExceeded))

        tracker.operationStarted()
        tracker.accountChanged(unavailableReason: .noAccount)
        XCTAssertEqual(tracker.status, .unavailable(.noAccount))
        XCTAssertEqual(tracker.activeOperationCount, 0)
    }
}
