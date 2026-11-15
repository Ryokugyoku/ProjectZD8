import Foundation
import XCTest
@testable import ProjectZD8

/// 一時停止中の猶予の起点が、一時停止に入った時刻ではなく最後の正応答を受信した時刻であることを検証します。
///
/// 応答途絶では最後の受信から途絶閾値(3秒)が経ってから一時停止に入るため、最後の受信と一時停止の開始がずれます。
/// そのずれの中に判定の時点を置き、起点の違いで結果が変わる境界を確かめます。
@MainActor
final class LiveTelemetryAcquisitionLoopPauseGraceOriginTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace = AcquisitionGracePeriodPolicy.gracePeriodNanoseconds
    /// 最後の正応答を受ける実時刻です。
    private let lastReceivedAt = Date(timeIntervalSince1970: 7_000)
    /// 判定の時点の実時刻です。終了時刻に使われないことを確かめるため、最後の受信と変えます。
    private let laterDate = Date(timeIntervalSince1970: 7_400)
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

    /// 最後の受信から猶予の1ナノ秒前に始めた復帰が、最後の受信から猶予を1ナノ秒超えて成功した場合は猶予切れです。
    ///
    /// 責務: 一時停止の開始からは猶予未満でも、成功が確定した時点の最後の受信からの経過で判定することを確認します(仕様 1・3・5)。
    func testResumeSucceedingAfterGraceSinceLastReceiveExpires() async {
        let (fixture, collector, lastReceived) = await pauseAfterStall()
        fixture.linkRecovery.schedule([true])
        fixture.advanceClock(to: lastReceived + grace - 1)
        await fixture.loop.notify(.foregroundEntered)
        await fixture.waitForSentRequests(3)

        fixture.advanceClock(to: lastReceived + grace + 1)
        await fixture.telemetry.release(.responded([5]))

        await fixture.assertExpired(collector, cause: .responseStall, lastReceivedAt: lastReceivedAt)
    }

    /// 最後の受信から猶予を1ナノ秒超えた起床では、一時停止の開始から猶予未満でも復帰を試さずに猶予切れです。
    ///
    /// 責務: 起床時の判定も最後の受信を起点にし、回復操作を呼ばずに終わることを確認します(仕様 1・2・5)。
    func testWakeAfterGraceSinceLastReceiveTerminatesWithoutAttempt() async {
        let (fixture, collector, lastReceived) = await pauseAfterStall()
        let callsBefore = fixture.linkRecovery.calls.count
        fixture.linkRecovery.schedule([true])
        fixture.advanceClock(to: lastReceived + grace + 1)

        await fixture.loop.notify(.foregroundEntered)

        await fixture.assertExpired(collector, cause: .responseStall, lastReceivedAt: lastReceivedAt)
        XCTAssertEqual(fixture.linkRecovery.calls.count, callsBefore, "猶予切れの起床では試さない")
    }

    /// 最後の受信からちょうど猶予の時点で復帰に成功すれば続行します。
    ///
    /// 責務: 境界ちょうどは続行で、欠損(開始=最後の受信、原因=応答途絶)を挟んで区間を再開することを確認します(仕様 2・6)。
    func testResumeAtExactlyGraceSinceLastReceiveContinues() async {
        await assertResume(atElapsedSinceLastReceive: grace)
    }

    /// 最後の受信から猶予の1ナノ秒前に復帰に成功すれば続行します。
    ///
    /// 責務: 境界の直前は続行で、欠損を挟んで区間を再開することを確認します(仕様 2・6)。
    func testResumeJustBeforeGraceSinceLastReceiveContinues() async {
        await assertResume(atElapsedSinceLastReceive: grace - 1)
    }

    /// 一時停止中の猶予切れの期限待ちは、最後の受信から猶予を過ぎる時点までです。
    ///
    /// 責務: 期限待ちに渡す値が最後の受信+猶予の直後(猶予切れと判定される最初の値)で、一時停止の開始+猶予の直後ではないことを確認します(仕様 4)。
    func testPauseDeadlineIsMeasuredFromLastReceive() async {
        let (fixture, _, lastReceived) = await pauseAfterStall()
        let pausedAt = fixture.clock.nowNanoseconds()

        await fixture.deadlineWaiter.waitForPending(lastReceived + grace + 1)

        XCTAssertFalse(fixture.deadlineWaiter.requestedDeadlines.contains(pausedAt + grace + 1))
    }

    /// 応答途絶の一時停止から指定の経過の時点で再初期化と確認要求が成功すれば続行することを検証します。
    ///
    /// 責務: 復帰の試行が1回だけで、取得中へ戻り、欠損を挟んで区間を再開することを確認します。
    /// - Parameters:
    ///   - elapsed: 確認要求の正応答を返す時点の、最後の受信からの単調時計の経過。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    private func assertResume(
        atElapsedSinceLastReceive elapsed: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let (fixture, collector, lastReceived) = await pauseAfterStall(file: file, line: line)
        let callsBefore = fixture.linkRecovery.calls.count
        fixture.linkRecovery.schedule([true])
        fixture.advanceClock(to: lastReceived + elapsed, file: file, line: line)

        await fixture.loop.notify(.foregroundEntered)
        await fixture.telemetry.release(.responded([5]), file: file, line: line)

        await fixture.assertContinued(collector, cause: .responseStall, lastReceivedAt: lastReceivedAt, sentRequests: 4, file: file, line: line)
        XCTAssertEqual(fixture.linkRecovery.calls.count, callsBefore + 1, file: file, line: line)
        XCTAssertEqual(fixture.linkRecovery.calls.last, .reinitializeFromReset, file: file, line: line)
    }

    /// 最後の正応答を `lastReceivedAt` で受けた後に応答途絶させ、回復を使い切った一時停止まで進めます。
    ///
    /// 責務: 一時停止の開始が最後の受信より後(途絶閾値の分)になっていることを前提として確かめます。
    /// - Parameters:
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: ループ部品、購読、最後の正応答を受けた時点の単調時計の値。
    private func pauseAfterStall(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> (LiveTelemetryAcquisitionLoopFixture, LiveTelemetryAcquisitionEventCollector, UInt64) {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        fixture.dates.set(lastReceivedAt)
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: .responseStall, file: file, line: line)
        await fixture.waitForPause(of: collector, file: file, line: line)
        XCTAssertEqual(
            fixture.clock.nowNanoseconds(), lastReceived + AcquisitionStallPolicy.stallThresholdNanoseconds,
            "一時停止の開始は最後の受信から途絶閾値の後", file: file, line: line
        )
        fixture.dates.set(laterDate)
        return (fixture, collector, lastReceived)
    }
}
