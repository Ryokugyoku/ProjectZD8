import Foundation
import XCTest
@testable import ProjectZD8

/// `SystemAdapterLinkSupervisionClock` の現在時刻と待機・キャンセルを検証します。
@MainActor
final class SystemAdapterLinkSupervisionClockTests: XCTestCase {
    /// 現在時刻は実時刻を返します。
    ///
    /// 責務: 呼び出し前後の `Date()` の間に収まることを確認します。
    func testNowReturnsWallClockTime() {
        let clock = SystemAdapterLinkSupervisionClock()
        let before = Date()
        let now = clock.now
        let after = Date()
        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThanOrEqual(now, after)
    }

    /// 待機は指定時間が経ってから戻ります。
    ///
    /// 責務: 50ミリ秒の待機が成功で終わり、少なくとも指定時間かかることを確認します。
    func testSleepReturnsAfterRequestedDuration() async {
        let clock = SystemAdapterLinkSupervisionClock()
        let monotonic = ContinuousClock()
        let start = monotonic.now
        let outcome = await AdapterLinkBoundedAwait.run("50ミリ秒の待機") { try await clock.sleep(for: .milliseconds(50)) }
        XCTAssertNotNil(AdapterLinkBoundedAwait.successValue(outcome))
        XCTAssertGreaterThanOrEqual(monotonic.now - start, .milliseconds(50))
    }

    /// 待機はキャンセルで早期に終わります。
    ///
    /// 責務: 10分の待機をキャンセルすると `CancellationError` で上限内に終わることを確認します。
    func testSleepEndsEarlyOnCancellation() async throws {
        let clock = SystemAdapterLinkSupervisionClock()
        let monotonic = ContinuousClock()
        let start = monotonic.now
        let task = Task { @MainActor in try await clock.sleep(for: .seconds(600)) }
        try await BLEBoundedWaiter.settle(polls: 5)
        task.cancel()
        let outcome = await AdapterLinkBoundedAwait.outcome(of: task, "キャンセルした待機")
        guard case .failure(let error)? = outcome else { return XCTFail("失敗で終わるはず: \(String(describing: outcome))") }
        XCTAssertTrue(error is CancellationError, "実際のエラー: \(error)")
        XCTAssertLessThan(monotonic.now - start, .seconds(10))
    }
}
