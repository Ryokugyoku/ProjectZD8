import XCTest
@testable import ProjectZD8

/// 一時停止中の起床理由ごとの動作の判定を検証します。
final class LiveTelemetryPauseWakeEvaluatorTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace: UInt64 = 180 * 1_000_000_000
    /// 定期試行の10秒です(ナノ秒)。
    private let retry: UInt64 = 10 * 1_000_000_000
    /// 最後の受信と一時停止の時点をどちらも0にした窓です。
    private let window = LiveTelemetryPauseWindow(pausedAtNanoseconds: 0, grace: .init(lastReceivedNanoseconds: 0))

    /// フォアグラウンド復帰とリンク復帰は、原因に応じた段階で復帰を試します。
    ///
    /// 責務: 復帰を試す2つの通知と、リンク断→再接続・応答途絶→ATZ再初期化の対応を確認します。
    func testForegroundAndLinkRestoredAttemptResume() {
        for signal in [LiveTelemetryAcquisitionWakeSignal.foregroundEntered, .linkRestored] {
            XCTAssertEqual(action(.signal(signal), now: 1, cause: .linkLost), .attemptResume(.reconnectLink), "\(signal)")
            XCTAssertEqual(action(.signal(signal), now: 1, cause: .responseStall), .attemptResume(.reinitializeFromReset), "\(signal)")
        }
    }

    /// バックグラウンド移行とリンク断は待ち続けます。
    ///
    /// 責務: 復帰を試さない2つの通知を確認します。
    func testBackgroundAndLinkLostKeepWaiting() {
        XCTAssertEqual(action(.signal(.backgroundEntered), now: 1, cause: .linkLost), .keepWaiting)
        XCTAssertEqual(action(.signal(.linkLost), now: 1, cause: .responseStall), .keepWaiting)
    }

    /// 期限到達は猶予内(ちょうど3分を含む)なら待ち直し、猶予超過なら終了です。
    ///
    /// 責務: 期限到達の境界値を確認します。
    func testDeadlineReachedRearmsWithinGraceAndTerminatesAfter() {
        XCTAssertEqual(action(.deadlineReached, now: grace, cause: .linkLost), .rearmDeadline)
        XCTAssertEqual(action(.deadlineReached, now: grace + 1, cause: .linkLost), .terminate)
    }

    /// 定期試行の起床は、試行時刻に達していれば復帰を試し、達していなければ待ち直します。
    ///
    /// 責務: 試行時刻の境界値と、空回りしない判定を確認します。
    func testRetryDueAttemptsOnlyWhenDue() {
        XCTAssertEqual(action(.retryDue, now: retry - 1, cause: .linkLost), .rearmRetry)
        XCTAssertEqual(action(.retryDue, now: retry, cause: .linkLost), .attemptResume(.reconnectLink))
        XCTAssertEqual(action(.retryDue, now: retry, cause: .responseStall), .attemptResume(.reinitializeFromReset))
    }

    /// 猶予を過ぎていれば、起床理由にかかわらず終了です。
    ///
    /// 責務: 猶予判定がすべての起床理由に優先することを確認します。
    func testExpiredGraceTerminatesForEveryReason() {
        let reasons: [LiveTelemetryPauseWakeReason] = [
            .deadlineReached, .retryDue, .signal(.foregroundEntered), .signal(.backgroundEntered),
            .signal(.linkRestored), .signal(.linkLost)
        ]
        for reason in reasons {
            XCTAssertEqual(action(reason, now: grace + 1, cause: .linkLost), .terminate, "\(reason)")
        }
    }

    /// 最後の受信と一時停止の開始が異なるとき、猶予切れは最後の受信から、定期試行は一時停止の開始から数えます。
    ///
    /// 責務: 2つの起点を分けた窓で、期限到達・通知・定期試行の境界を確認します。
    func testGraceCountsFromLastReceiveAndRetryFromPause() {
        let pausedAt: UInt64 = 40 * 1_000_000_000
        let split = LiveTelemetryPauseWindow(pausedAtNanoseconds: pausedAt, grace: .init(lastReceivedNanoseconds: 0))
        let evaluator = LiveTelemetryPauseWakeEvaluator()
        func act(_ reason: LiveTelemetryPauseWakeReason, _ now: UInt64) -> LiveTelemetryPauseWakeAction {
            evaluator.action(for: reason, window: split, nowNanoseconds: now, cause: .linkLost)
        }

        XCTAssertEqual(act(.deadlineReached, grace), .rearmDeadline)
        XCTAssertEqual(act(.deadlineReached, grace + 1), .terminate, "一時停止の開始からは猶予内でも終了")
        XCTAssertEqual(act(.signal(.foregroundEntered), grace + 1), .terminate)
        XCTAssertEqual(act(.signal(.foregroundEntered), grace), .attemptResume(.reconnectLink))
        XCTAssertEqual(act(.retryDue, retry), .rearmRetry, "最後の受信から10秒では試さない")
        XCTAssertEqual(act(.retryDue, pausedAt + retry - 1), .rearmRetry)
        XCTAssertEqual(act(.retryDue, pausedAt + retry), .attemptResume(.reconnectLink))
    }

    /// 原因ごとの復帰段階は、リンク断なら再接続、応答途絶ならATZ再初期化です。
    ///
    /// 責務: 復帰段階の対応を確認します。
    func testResumeStageForCause() {
        XCTAssertEqual(LiveTelemetryPauseWakeEvaluator().resumeStage(for: .linkLost), .reconnectLink)
        XCTAssertEqual(LiveTelemetryPauseWakeEvaluator().resumeStage(for: .responseStall), .reinitializeFromReset)
    }

    /// 起床理由の動作を判定します。
    ///
    /// 責務: 固定の窓で評価器を呼びます。
    /// - Parameters:
    ///   - reason: 起床理由。
    ///   - now: 単調時計の現在値。
    ///   - cause: 途絶の原因。
    /// - Returns: 判定された動作。
    private func action(_ reason: LiveTelemetryPauseWakeReason, now: UInt64, cause: LiveTelemetryInterruptionCause) -> LiveTelemetryPauseWakeAction {
        LiveTelemetryPauseWakeEvaluator().action(for: reason, window: window, nowNanoseconds: now, cause: cause)
    }
}
