import Foundation
import XCTest
@testable import ProjectZD8

/// `SystemAdapterLinkSupervisionClock` の現在時刻と待機・キャンセルを検証します。
@MainActor
final class SystemAdapterLinkSupervisionClockTests: XCTestCase {
    /// 現在時刻は、生成時の実時刻を起点にします。
    ///
    /// 責務: 単調時計が進んでいない時の現在時刻が、生成の前後の `Date()` の間に収まることを確認します(U3 受け入れ条件 4)。
    func testNowStartsAtWallClockTimeOfCreation() {
        let before = Date()
        let clock = SystemAdapterLinkSupervisionClock(monotonic: ManualMonotonicClock(initialNanoseconds: 5_000))
        let after = Date()
        XCTAssertGreaterThanOrEqual(clock.now, before)
        XCTAssertLessThanOrEqual(clock.now, after)
    }

    /// 現在時刻は、注入した単調時計の経過だけで進み、単調時計が進まなければ変わりません。
    ///
    /// 責務: 単調時計を止めたままの2回の読み取りが同じで、5秒・さらに0.5秒進めた分だけ進むことを確認します(実時刻の変更に影響されない。U3 受け入れ条件 4)。
    func testNowAdvancesOnlyWithMonotonicClock() {
        let monotonic = ManualMonotonicClock(initialNanoseconds: 1_000)
        let clock = SystemAdapterLinkSupervisionClock(monotonic: monotonic)
        let origin = clock.now
        XCTAssertEqual(clock.now, origin)

        monotonic.advance(byNanoseconds: 5_000_000_000)
        XCTAssertEqual(clock.now.timeIntervalSince(origin), 5, accuracy: 1e-6)
        monotonic.advance(byNanoseconds: 500_000_000)
        XCTAssertEqual(clock.now.timeIntervalSince(origin), 5.5, accuracy: 1e-6)
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
