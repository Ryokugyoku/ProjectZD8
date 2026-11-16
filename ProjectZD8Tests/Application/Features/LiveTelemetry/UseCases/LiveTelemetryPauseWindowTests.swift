import XCTest
@testable import ProjectZD8

/// 一時停止の猶予判定・猶予の期限・定期試行の予定を検証します。
///
/// 仕様: 猶予の判定と期限は最後の受信から数え、定期試行は一時停止の開始(または直前の試行の終了)から数えます。
/// 両者を区別するため、最後の受信と一時停止の開始を別の値にします。
final class LiveTelemetryPauseWindowTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace: UInt64 = 180 * 1_000_000_000
    /// 定期試行の10秒です(ナノ秒)。
    private let retry: UInt64 = 10 * 1_000_000_000
    /// 最後の受信の単調時計の値です。
    private let lastReceived: UInt64 = 1_000
    /// 一時停止を始めた単調時計の値です(最後の受信から40秒後)。
    private let pausedAt: UInt64 = 1_000 + 40 * 1_000_000_000

    /// 最後の受信からちょうど3分とその直前は続行、直後は終了で、一時停止の開始からの経過では判定しません。
    ///
    /// 責務: 猶予判定の境界値・起点・逆行を確認します。
    func testDecisionBoundariesAreMeasuredFromLastReceive() {
        let window = makeWindow()

        XCTAssertEqual(window.decision(nowNanoseconds: lastReceived + grace - 1), .continueWaiting)
        XCTAssertEqual(window.decision(nowNanoseconds: lastReceived + grace), .continueWaiting)
        XCTAssertEqual(window.decision(nowNanoseconds: lastReceived + grace + 1), .terminate)
        XCTAssertEqual(window.decision(nowNanoseconds: pausedAt + grace), .terminate, "一時停止の開始からは猶予内でも終了")
        XCTAssertEqual(window.decision(nowNanoseconds: 0), .continueWaiting, "逆行は経過0")
    }

    /// 猶予の期限は最後の受信 + 3分 + 1ナノ秒で、桁あふれは最大値に揃えます。
    ///
    /// 責務: 期限が一時停止の開始ではなく最後の受信から決まることと、桁あふれを確認します。
    func testDeadlineIsMeasuredFromLastReceive() {
        XCTAssertEqual(makeWindow().deadlineNanoseconds, lastReceived + grace + 1)
        XCTAssertNotEqual(makeWindow().deadlineNanoseconds, pausedAt + grace + 1)
        let overflowing = LiveTelemetryPauseWindow(pausedAtNanoseconds: .max - 1, grace: .init(lastReceivedNanoseconds: .max - 5))
        XCTAssertEqual(overflowing.deadlineNanoseconds, .max)
    }

    /// 最初の定期試行は最後の受信ではなく一時停止の開始から10秒後で、その時刻ちょうどから試行時刻に達します。
    ///
    /// 責務: 定期試行の初期値・起点・判定の境界値を確認します。
    func testFirstRetryIsTenSecondsAfterPause() {
        let window = makeWindow()

        XCTAssertEqual(window.nextRetryNanoseconds, pausedAt + retry)
        XCTAssertFalse(window.isRetryDue(nowNanoseconds: lastReceived + retry), "最後の受信から10秒では試さない")
        XCTAssertFalse(window.isRetryDue(nowNanoseconds: pausedAt + retry - 1))
        XCTAssertTrue(window.isRetryDue(nowNanoseconds: pausedAt + retry))
    }

    /// 次の定期試行は直前の試行の終了から10秒後で、一時停止より前の終了時刻は一時停止に揃え、桁あふれは最大値です。
    ///
    /// 責務: 次の試行の予定の基準と境界と、予定を変えても猶予の期限が変わらないことを確認します。
    func testScheduleNextRetryFromAttemptEnd() {
        var window = makeWindow()
        window.scheduleNextRetry(afterAttemptEndedAt: pausedAt + 30_000)
        XCTAssertEqual(window.nextRetryNanoseconds, pausedAt + 30_000 + retry)
        window.scheduleNextRetry(afterAttemptEndedAt: lastReceived)
        XCTAssertEqual(window.nextRetryNanoseconds, pausedAt + retry, "一時停止より前は一時停止に揃える")
        XCTAssertEqual(window.deadlineNanoseconds, lastReceived + grace + 1, "定期試行の予定は猶予の期限を動かさない")
        var overflowing = LiveTelemetryPauseWindow(pausedAtNanoseconds: 0, grace: .init(lastReceivedNanoseconds: 0))
        overflowing.scheduleNextRetry(afterAttemptEndedAt: .max - 1)
        XCTAssertEqual(overflowing.nextRetryNanoseconds, .max)
    }

    /// 最後の受信と一時停止の開始を分けた窓を作ります。
    ///
    /// 責務: 既定の起点で窓を返します。
    /// - Returns: 一時停止の窓。
    private func makeWindow() -> LiveTelemetryPauseWindow {
        LiveTelemetryPauseWindow(pausedAtNanoseconds: pausedAt, grace: .init(lastReceivedNanoseconds: lastReceived))
    }
}
