import Foundation
import XCTest
@testable import ProjectZD8

/// 取得ループの一時停止中の猶予、復帰の試行、起床の種類ごとの動作、猶予切れの終了を検証します。
///
/// 時間は手動の単調時計・実時刻clockと、テストが解放する期限待ちだけで進めます。
@MainActor
final class LiveTelemetryAcquisitionLoopPauseTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace: UInt64 = 180 * 1_000_000_000
    /// 定期試行の間隔の10秒です(ナノ秒)。
    private let retry: UInt64 = 10 * 1_000_000_000
    /// 各テストのループ部品です。
    private var fixture: LiveTelemetryAcquisitionLoopFixture?

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 一時停止からちょうど3分の時点で復帰に成功すれば続行します。
    ///
    /// 責務: 猶予ちょうどのフォアグラウンド復帰での再接続と確認要求の成功が再開になることを確認します。
    func testResumeAtExactlyGraceContinues() async {
        await assertResume(afterPausedFor: 180 * 1_000_000_000)
    }

    /// 一時停止から3分の1ナノ秒前に復帰に成功すれば続行します。
    ///
    /// 責務: 猶予の直前の復帰が再開になることを確認します。
    func testResumeJustBeforeGraceContinues() async {
        await assertResume(afterPausedFor: 180 * 1_000_000_000 - 1)
    }

    /// 一時停止から3分を1ナノ秒過ぎた起床では、復帰を試さずに猶予切れで終わります。
    ///
    /// 責務: 猶予超過の起床が回復操作を呼ばずに `gracePeriodExpired` になることを確認します。
    func testWakeJustAfterGraceTerminatesWithoutAttempt() async {
        let fixture = make()
        let (collector, _) = await fixture.startAndPause(cause: .linkLost)
        let callsBefore = fixture.linkRecovery.calls.count
        fixture.linkRecovery.schedule([true])
        fixture.clock.advance(byNanoseconds: grace + 1)

        await fixture.loop.notify(.foregroundEntered)
        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .gracePeriodExpired(cause: .linkLost, lastReceivedAt: LiveTelemetryAcquisitionLoopFixture.fixedNow))
        XCTAssertEqual(fixture.linkRecovery.calls.count, callsBefore)
    }

    /// 猶予切れの終了時刻は、終了を判定した時刻ではなく最後に正常応答を受けた実時刻で、原因がリンク断なら接続断です。
    ///
    /// 責務: 最後の受信と判定時の実時刻を変えて、終了理由・終了時刻と記録の終了原因を確認します。
    func testExpiryAfterLinkLossEndsAtLastReceiveAsConnectionLost() async {
        let fixture = make()
        let lastReceive = Date(timeIntervalSince1970: 5_000)
        fixture.dates.set(lastReceive)
        let (collector, _) = await fixture.startAndPause(cause: .linkLost)
        fixture.dates.set(Date(timeIntervalSince1970: 5_500))
        fixture.clock.advance(byNanoseconds: grace + 1)

        await fixture.loop.notify(.linkRestored)
        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination?.sessionEndedAt, lastReceive)
        XCTAssertNotEqual(termination?.sessionEndedAt, fixture.dates.now())
        XCTAssertEqual(termination?.sessionEndReason, .connectionLost)
        let finishes = await fixture.recorder?.finishCalls
        XCTAssertEqual(finishes, [.finish(generation: 1, reason: .connectionLost)])
    }

    /// 応答途絶による猶予切れは、最後に正常応答を受けた実時刻で車両無応答として終わります。
    ///
    /// 責務: 応答途絶の原因が車両無応答の終了原因と最後の受信時刻になることを確認します。
    func testExpiryAfterStallEndsAtLastReceiveAsVehicleNoResponse() async {
        let fixture = make()
        let lastReceive = Date(timeIntervalSince1970: 7_000)
        fixture.dates.set(lastReceive)
        let (collector, pausedAt) = await fixture.startAndPause(cause: .responseStall)
        await fixture.deadlineWaiter.waitForPending(pausedAt + grace + 1)
        fixture.dates.set(Date(timeIntervalSince1970: 7_400))
        fixture.clock.advance(byNanoseconds: grace + 1)

        XCTAssertTrue(fixture.deadlineWaiter.release(deadline: pausedAt + grace + 1) > 0)
        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .gracePeriodExpired(cause: .responseStall, lastReceivedAt: lastReceive))
        XCTAssertEqual(termination?.sessionEndReason, .vehicleNoResponse)
    }

    /// 一時停止中は10秒ごとに復帰が試され、時計が進まないまま起床しても次の試行時刻までは試されません。
    ///
    /// 責務: 定期試行の期限・期限が早く返った場合の待ち直し・遅く返った場合の次の期限を単調時計で確認します。
    func testPeriodicRetryUsesMonotonicClockWithoutSpinning() async {
        let fixture = make()
        let (_, pausedAt) = await fixture.startAndPause(cause: .linkLost)
        let afterPause = fixture.linkRecovery.calls.count
        await fixture.deadlineWaiter.waitForPending(pausedAt + retry)
        XCTAssertEqual(fixture.deadlineWaiter.pendingDeadlines, [pausedAt + retry, pausedAt + grace + 1])

        fixture.clock.advance(byNanoseconds: retry)
        fixture.deadlineWaiter.release(deadline: pausedAt + retry)
        await fixture.linkRecovery.waitForCalls(afterPause + 1)
        await fixture.deadlineWaiter.waitForPending(pausedAt + 2 * retry)
        XCTAssertEqual(fixture.linkRecovery.calls.last, .reconnectLink)

        for _ in 0..<3 {
            fixture.deadlineWaiter.release(deadline: pausedAt + 2 * retry)
            await fixture.deadlineWaiter.waitForPending(pausedAt + 2 * retry)
        }
        await LiveTelemetryBoundedWaiter.settle()
        XCTAssertEqual(fixture.linkRecovery.calls.count, afterPause + 1, "時計が進まない起床では試さない")

        fixture.clock.advance(byNanoseconds: 25 * 1_000_000_000)
        fixture.deadlineWaiter.release(deadline: pausedAt + 2 * retry)
        await fixture.linkRecovery.waitForCalls(afterPause + 2)
        await fixture.deadlineWaiter.waitForPending(pausedAt + 45 * 1_000_000_000)
        XCTAssertEqual(fixture.deadlineWaiter.pendingDeadlines, [pausedAt + 45 * 1_000_000_000, pausedAt + grace + 1])
    }

    /// 猶予の期限待ちが猶予内に返っても終わらず、同じ期限で待ち直し、猶予を過ぎて返れば終わります。
    ///
    /// 責務: 早く返った期限到達で終了しないことと、猶予超過の期限到達で終了することを確認します。
    func testEarlyDeadlineRearmsAndLateDeadlineTerminates() async {
        let fixture = make()
        let (collector, pausedAt) = await fixture.startAndPause(cause: .linkLost)
        let deadline = pausedAt + grace + 1
        await fixture.deadlineWaiter.waitForPending(deadline)

        fixture.clock.advance(byNanoseconds: 100 * 1_000_000_000)
        fixture.deadlineWaiter.release(deadline: deadline)
        await fixture.deadlineWaiter.waitForPending(deadline)
        XCTAssertNil(collector.termination)

        fixture.clock.advance(byNanoseconds: 80 * 1_000_000_000 + 1)
        fixture.deadlineWaiter.release(deadline: deadline)
        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .gracePeriodExpired(cause: .linkLost, lastReceivedAt: LiveTelemetryAcquisitionLoopFixture.fixedNow))
    }

    /// バックグラウンド移行とリンク断の通知では待ち続け、リンク復帰では原因に応じた段階で復帰を試します。
    ///
    /// 責務: 起床の通知ごとに回復操作の有無と段階を確認します。
    func testWakeSignalsDecideWhetherToAttempt() async {
        let fixture = make()
        let (collector, _) = await fixture.startAndPause(cause: .linkLost)
        let afterPause = fixture.linkRecovery.calls.count

        await fixture.loop.notify(.backgroundEntered)
        await fixture.loop.notify(.linkLost)
        await LiveTelemetryBoundedWaiter.settle()
        XCTAssertEqual(fixture.linkRecovery.calls.count, afterPause)
        await fixture.loop.notify(.linkRestored)
        await fixture.linkRecovery.waitForCalls(afterPause + 1)

        XCTAssertEqual(fixture.linkRecovery.calls.last, .reconnectLink)
        XCTAssertNil(collector.termination)
    }

    /// 応答途絶による一時停止からの復帰は ATZ 再初期化で試します。
    ///
    /// 責務: 原因が応答途絶の場合の復帰段階を確認します。
    func testStallPauseResumesWithReinitialize() async {
        let fixture = make()
        _ = await fixture.startAndPause(cause: .responseStall)
        let afterPause = fixture.linkRecovery.calls.count

        await fixture.loop.notify(.foregroundEntered)
        await fixture.linkRecovery.waitForCalls(afterPause + 1)

        XCTAssertEqual(fixture.linkRecovery.calls.last, .reinitializeFromReset)
    }

    /// 猶予内に始めた復帰の試行が猶予を過ぎて終わった場合は、成功しても猶予切れで終わります。
    ///
    /// 責務: 確認要求の応答待ちの間に猶予を過ぎた成功が再開にならないことを確認します。
    func testAttemptCrossingGraceDeadlineTerminatesEvenIfSuccessful() async {
        let fixture = make()
        let (collector, _) = await fixture.startAndPause(cause: .linkLost)
        fixture.linkRecovery.schedule([true])
        fixture.clock.advance(byNanoseconds: grace - 1_000_000_000)
        await fixture.loop.notify(.foregroundEntered)
        await fixture.telemetry.waitForSentRequests(3)

        fixture.clock.advance(byNanoseconds: 1_000_000_000 + 1)
        await fixture.telemetry.release(.responded([9]))
        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .gracePeriodExpired(cause: .linkLost, lastReceivedAt: LiveTelemetryAcquisitionLoopFixture.fixedNow))
        let segments = await fixture.recorder?.segmentCalls ?? []
        XCTAssertEqual(segments.count, 1, "区間は再開されない")
    }

    /// 一時停止中にユーザーが停止すると、猶予を待たずにユーザー切断で終わり、期限待ちを残しません。
    ///
    /// 責務: 一時停止からの停止の終了理由・記録の終了原因・期限待ちの解放を確認します。
    func testStopDuringPauseEndsImmediately() async {
        let fixture = make()
        _ = await fixture.startAndPause(cause: .responseStall)
        await fixture.deadlineWaiter.waitForPending(fixture.clock.nowNanoseconds() + retry)

        let termination = await fixture.loop.stop()

        XCTAssertEqual(termination, .stopped)
        XCTAssertEqual(fixture.deadlineWaiter.pendingDeadlines, [])
        let finishes = await fixture.recorder?.finishCalls
        XCTAssertEqual(finishes, [.finish(generation: 1, reason: .userDisconnected)])
    }

    /// 一時停止から指定時間の後のフォアグラウンド復帰で、再接続と確認要求が成功すれば続行することを検証します。
    ///
    /// 責務: 再接続の1回だけで再開し、区間を再開して次の周回の要求を送り、終了しないことを確認します。
    /// - Parameters:
    ///   - elapsed: 一時停止からの経過(ナノ秒)。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    private func assertResume(afterPausedFor elapsed: UInt64, file: StaticString = #filePath, line: UInt = #line) async {
        let fixture = make()
        let (collector, _) = await fixture.startAndPause(cause: .linkLost, file: file, line: line)
        let callsBefore = fixture.linkRecovery.calls.count
        fixture.linkRecovery.schedule([true])
        fixture.clock.advance(byNanoseconds: elapsed)

        await fixture.loop.notify(.foregroundEntered)
        await fixture.telemetry.release(.responded([5]), file: file, line: line)
        await fixture.telemetry.waitForSentRequests(4, file: file, line: line)

        XCTAssertEqual(fixture.linkRecovery.calls.count, callsBefore + 1, file: file, line: line)
        XCTAssertEqual(fixture.linkRecovery.calls.last, .reconnectLink, file: file, line: line)
        XCTAssertEqual(collector.phases.last, .acquiring, file: file, line: line)
        XCTAssertNil(collector.termination, file: file, line: line)
        let segments = await fixture.recorder?.segmentCalls ?? []
        XCTAssertEqual(segments.count, 2, file: file, line: line)
    }

    /// 記録ポートのスパイ付きの部品を生成して後片付けの対象にします。
    ///
    /// 責務: 既定の記録ポートを持つループ部品を返します。
    /// - Returns: ループ部品。
    private func make() -> LiveTelemetryAcquisitionLoopFixture {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        return fixture
    }
}
