import XCTest
@testable import ProjectZD8

/// `BLEAdapterLinkRetryCounter` の失敗計数・上限判定・初期化を検証します。
final class BLEAdapterLinkRetryCounterTests: XCTestCase {
    /// 負の上限は0として扱います。
    ///
    /// 責務: 生成時の丸めと、上限0で最初の失敗が再接続不可になることを確認します。
    func testNegativeMaximumIsClampedToZero() {
        var counter = BLEAdapterLinkRetryCounter(maximumConsecutiveReconnects: -3)
        XCTAssertEqual(counter.maximumConsecutiveReconnects, 0)
        XCTAssertFalse(counter.recordFailure())
    }

    /// 生成直後の失敗数は0です。
    ///
    /// 責務: 初期状態の計数を確認します。
    func testInitialFailureCountIsZero() {
        let counter = BLEAdapterLinkRetryCounter(maximumConsecutiveReconnects: 2)
        XCTAssertEqual(counter.consecutiveFailures, 0)
        XCTAssertEqual(counter.maximumConsecutiveReconnects, 2)
    }

    /// 上限ちょうどまでは再接続可、上限を超えると不可になります。
    ///
    /// 責務: 上限2で1・2回目が `true`、3・4回目が `false` で、失敗数が毎回1増えることを確認します。
    func testRecordFailureAllowsUpToMaximumAndRejectsBeyond() {
        var counter = BLEAdapterLinkRetryCounter(maximumConsecutiveReconnects: 2)
        XCTAssertTrue(counter.recordFailure())
        XCTAssertEqual(counter.consecutiveFailures, 1)
        XCTAssertTrue(counter.recordFailure())
        XCTAssertEqual(counter.consecutiveFailures, 2)
        XCTAssertFalse(counter.recordFailure())
        XCTAssertEqual(counter.consecutiveFailures, 3)
        XCTAssertFalse(counter.recordFailure())
    }

    /// 上限0では最初の失敗から再接続不可です。
    ///
    /// 責務: 境界の上限0を確認します。
    func testZeroMaximumRejectsFirstFailure() {
        var counter = BLEAdapterLinkRetryCounter(maximumConsecutiveReconnects: 0)
        XCTAssertFalse(counter.recordFailure())
    }

    /// `reset()` で失敗数が0に戻り、再び上限まで再接続できます。
    ///
    /// 責務: 上限超過後のリセットで計数が初期化されることを確認します。
    func testResetClearsFailuresAndAllowsRetryAgain() {
        var counter = BLEAdapterLinkRetryCounter(maximumConsecutiveReconnects: 1)
        _ = counter.recordFailure()
        XCTAssertFalse(counter.recordFailure())

        counter.reset()

        XCTAssertEqual(counter.consecutiveFailures, 0)
        XCTAssertTrue(counter.recordFailure())
        XCTAssertFalse(counter.recordFailure())
    }
}
