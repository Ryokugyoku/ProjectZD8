import Foundation
import XCTest
@testable import ProjectZD8

/// 一時停止に入る前の回復段階でも、猶予(最後の正応答の受信から3分)を超えたら続行しないことを検証します。
///
/// 猶予の起点は最後の正応答を受信した単調時刻で、経過が猶予以下なら続行、超えたら猶予切れです。
/// 時間は手動の単調時計・実時刻clockと、テストが解放する確認要求の応答だけで進めます。
@MainActor
final class LiveTelemetryAcquisitionLoopRecoveryGraceTests: XCTestCase {
    /// 猶予の3分です(ナノ秒)。
    private let grace = AcquisitionGracePeriodPolicy.gracePeriodNanoseconds
    /// 最後の正応答を受ける実時刻です。
    private let lastReceivedAt = Date(timeIntervalSince1970: 5_000)
    /// 判定の時点の実時刻です。終了時刻に使われないことを確かめるため、最後の受信と変えます。
    private let laterDate = Date(timeIntervalSince1970: 5_900)
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

    /// リンク断の回復段階で、最後の受信から猶予を1ナノ秒超えて回復に成功しても、猶予切れで終わります。
    ///
    /// 責務: 一時停止前の回復の成功でも経過を判定し、続行せずに最後の受信の実時刻・接続断で終わることを確認します(仕様 1・3・5)。
    func testLinkLossRecoverySuccessAfterGraceExpires() async {
        let (fixture, collector) = await succeedFirstAttempt(cause: .linkLost, elapsedSinceLastReceive: grace + 1)

        await fixture.assertExpired(collector, cause: .linkLost, lastReceivedAt: lastReceivedAt)
    }

    /// 応答途絶の回復段階で、最後の受信から猶予を1ナノ秒超えて回復に成功しても、猶予切れで終わります。
    ///
    /// 責務: 一時停止前の回復の成功でも経過を判定し、続行せずに最後の受信の実時刻・車両無応答で終わることを確認します(仕様 1・3・5)。
    func testStallRecoverySuccessAfterGraceExpires() async {
        let (fixture, collector) = await succeedFirstAttempt(cause: .responseStall, elapsedSinceLastReceive: grace + 1)

        await fixture.assertExpired(collector, cause: .responseStall, lastReceivedAt: lastReceivedAt)
    }

    /// 回復段階で、最後の受信からちょうど猶予の時点で回復に成功すれば続行します。
    ///
    /// 責務: 境界ちょうどは続行で、欠損を挟んで同じセッションの区間を再開することを原因ごとに確認します(仕様 2・6)。
    func testRecoverySuccessAtExactlyGraceContinues() async {
        for cause in [LiveTelemetryInterruptionCause.linkLost, .responseStall] {
            let (fixture, collector) = await succeedFirstAttempt(cause: cause, elapsedSinceLastReceive: grace)

            await fixture.assertContinued(collector, cause: cause, lastReceivedAt: lastReceivedAt, sentRequests: 4)
            await fixture.tearDown()
        }
    }

    /// 回復段階で、最後の受信から猶予の1ナノ秒前に回復に成功すれば続行します。
    ///
    /// 責務: 境界の直前は続行で、欠損を挟んで同じセッションの区間を再開することを原因ごとに確認します(仕様 2・6)。
    func testRecoverySuccessJustBeforeGraceContinues() async {
        for cause in [LiveTelemetryInterruptionCause.linkLost, .responseStall] {
            let (fixture, collector) = await succeedFirstAttempt(cause: cause, elapsedSinceLastReceive: grace - 1)

            await fixture.assertContinued(collector, cause: cause, lastReceivedAt: lastReceivedAt, sentRequests: 4)
            await fixture.tearDown()
        }
    }

    /// 回復段階の途中で期限(最後の受信+猶予)を過ぎたら、次の試行を始めずに猶予切れで終わります。
    ///
    /// 責務: 1回目の試行の確認要求の応答待ちの間に期限を過ぎ、その試行が失敗した後、回復操作が増えないことを確認します(仕様 4)。
    func testRecoveryStopsStartingAttemptsAfterDeadline() async {
        let fixture = make()
        fixture.linkRecovery.schedule([true])
        fixture.dates.set(lastReceivedAt)
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: .linkLost)
        await fixture.waitForSentRequests(3)
        fixture.dates.set(laterDate)
        fixture.advanceClock(to: lastReceived + grace + 1)

        await fixture.telemetry.release(.timedOut)

        await fixture.assertExpired(collector, cause: .linkLost, lastReceivedAt: lastReceivedAt)
        XCTAssertEqual(fixture.linkRecovery.calls, [.promptResync], "期限後に次の試行を始めない")
    }

    /// 回復段階の途中でも、経過がちょうど猶予までなら次の試行へ進みます。
    ///
    /// 責務: 期限の境界ちょうどでは猶予切れにせず、次の試行を始めることを確認します(仕様 2・4)。
    func testRecoveryKeepsAttemptingAtExactlyGrace() async {
        let fixture = make()
        fixture.linkRecovery.schedule([true])
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: .linkLost)
        await fixture.waitForSentRequests(3)
        fixture.advanceClock(to: lastReceived + grace)

        await fixture.telemetry.release(.timedOut)
        await fixture.linkRecovery.waitForCalls(2)

        XCTAssertEqual(Array(fixture.linkRecovery.calls.prefix(2)), [.promptResync, .promptResync])
        XCTAssertNil(collector.termination)
    }

    /// 最後の回復段階の試行が期限を過ぎて失敗した場合、一時停止で試行も待機もせず直ちに猶予切れで終わります。
    ///
    /// 責務: 一時停止に入る時点で期限を過ぎていれば、回復操作を増やさず、期限待ちを要求せずに終わることを確認します(仕様 4)。
    func testPauseEntryAfterDeadlineExpiresWithoutAttemptOrWait() async {
        let fixture = make()
        fixture.linkRecovery.schedule(Array(repeating: false, count: 7) + [true])
        fixture.dates.set(lastReceivedAt)
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: .linkLost)
        await fixture.waitForSentRequests(3)
        XCTAssertEqual(fixture.linkRecovery.calls.count, 8, "最後の段階の最後の試行の確認要求")
        fixture.dates.set(laterDate)
        fixture.advanceClock(to: lastReceived + grace + 1)

        await fixture.telemetry.release(.timedOut)

        await fixture.assertExpired(collector, cause: .linkLost, lastReceivedAt: lastReceivedAt)
        XCTAssertEqual(fixture.linkRecovery.calls.count, 8, "期限後に試行しない")
        XCTAssertEqual(fixture.deadlineWaiter.requestedDeadlines, [], "期限後に待機しない")
    }

    /// 回復段階の1回目で回復操作を成功させ、確認要求の応答を指定の経過の時点で正応答として返します。
    ///
    /// 責務: 最後の正応答を `lastReceivedAt` で受け、途絶させ、確認要求の到着を待って時計を進めてから正応答を返します。
    /// - Parameters:
    ///   - cause: 起こす途絶の原因。
    ///   - elapsedSinceLastReceive: 正応答を返す時点の、最後の受信からの単調時計の経過。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    /// - Returns: ループ部品と購読。
    private func succeedFirstAttempt(
        cause: LiveTelemetryInterruptionCause,
        elapsedSinceLastReceive: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> (LiveTelemetryAcquisitionLoopFixture, LiveTelemetryAcquisitionEventCollector) {
        let fixture = make()
        fixture.linkRecovery.schedule([true])
        fixture.dates.set(lastReceivedAt)
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: cause, file: file, line: line)
        await fixture.waitForSentRequests(3, file: file, line: line)
        XCTAssertEqual(fixture.linkRecovery.calls, [.promptResync], file: file, line: line)
        fixture.dates.set(laterDate)
        fixture.advanceClock(to: lastReceived + elapsedSinceLastReceive, file: file, line: line)
        await fixture.telemetry.release(.responded([9]), file: file, line: line)
        return (fixture, collector)
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
