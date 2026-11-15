import XCTest
@testable import ProjectZD8

/// 一時停止の猶予判定・猶予の期限・定期試行の予定を検証します。
final class LiveTelemetryPauseWindowTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace: UInt64 = 180 * 1_000_000_000
    /// 定期試行の10秒です(ナノ秒)。
    private let retry: UInt64 = 10 * 1_000_000_000

    /// 一時停止からちょうど3分とその直前は続行、直後は終了、時計の逆行は経過0として続行です。
    ///
    /// 責務: 猶予判定の境界値と逆行を確認します。
    func testDecisionBoundaries() {
        let window = LiveTelemetryPauseWindow(pausedAtNanoseconds: 1_000)

        XCTAssertEqual(window.decision(nowNanoseconds: 1_000), .continueWaiting)
        XCTAssertEqual(window.decision(nowNanoseconds: 1_000 + grace - 1), .continueWaiting)
        XCTAssertEqual(window.decision(nowNanoseconds: 1_000 + grace), .continueWaiting)
        XCTAssertEqual(window.decision(nowNanoseconds: 1_000 + grace + 1), .terminate)
        XCTAssertEqual(window.decision(nowNanoseconds: 0), .continueWaiting)
    }

    /// 猶予の期限は終了と判定される最初の値(一時停止+3分+1ナノ秒)で、桁あふれは最大値に揃えます。
    ///
    /// 責務: 期限の値と桁あふれの扱いを確認します。
    func testDeadlineIsFirstTerminatingValue() {
        XCTAssertEqual(LiveTelemetryPauseWindow(pausedAtNanoseconds: 1_000).deadlineNanoseconds, 1_000 + grace + 1)
        XCTAssertEqual(LiveTelemetryPauseWindow(pausedAtNanoseconds: .max - 5).deadlineNanoseconds, .max)
    }

    /// 最初の定期試行は一時停止から10秒後で、その時刻ちょうどから試行時刻に達します。
    ///
    /// 責務: 定期試行の初期値と判定の境界値を確認します。
    func testFirstRetryIsTenSecondsAfterPause() {
        let window = LiveTelemetryPauseWindow(pausedAtNanoseconds: 500)

        XCTAssertEqual(window.nextRetryNanoseconds, 500 + retry)
        XCTAssertFalse(window.isRetryDue(nowNanoseconds: 500 + retry - 1))
        XCTAssertTrue(window.isRetryDue(nowNanoseconds: 500 + retry))
    }

    /// 次の定期試行は直前の試行の終了から10秒後で、一時停止より前の終了時刻は一時停止に揃え、桁あふれは最大値です。
    ///
    /// 責務: 次の試行の予定の基準と境界を確認します。
    func testScheduleNextRetryFromAttemptEnd() {
        var window = LiveTelemetryPauseWindow(pausedAtNanoseconds: 1_000)
        window.scheduleNextRetry(afterAttemptEndedAt: 30_000)
        XCTAssertEqual(window.nextRetryNanoseconds, 30_000 + retry)
        window.scheduleNextRetry(afterAttemptEndedAt: 10)
        XCTAssertEqual(window.nextRetryNanoseconds, 1_000 + retry)
        var overflowing = LiveTelemetryPauseWindow(pausedAtNanoseconds: 0)
        overflowing.scheduleNextRetry(afterAttemptEndedAt: .max - 1)
        XCTAssertEqual(overflowing.nextRetryNanoseconds, .max)
    }
}
