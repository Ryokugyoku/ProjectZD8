import Foundation
import XCTest
@testable import ProjectZD8

/// エンジン停止(車両応答なし)を、3分の猶予を待たずに30秒で切断扱いにすることを検証します。
///
/// OBD端子は常時給電のため、エンジンを切ってもアダプターは応答し、車両への要求だけが無応答になります。
/// 応答途絶のあと、回復でアダプターが応答する(プロンプト再同期またはATZ再初期化が成功する)のに確認要求が
/// 正応答にならない状態を「車両応答なし」とみなします。リンク断とアダプター自体の無応答は従来どおり3分の猶予です。
/// 時間は手動の単調時計・実時刻clockと、テストが解放する確認要求の応答だけで進めます(実時間の待機はしません)。
@MainActor
final class LiveTelemetryAcquisitionLoopVehicleOffTests: XCTestCase {
    /// 車両応答なしとみなす既定の経過(最後の受信から30秒、ナノ秒)です。
    private let vehicleOff: UInt64 = 30_000_000_000
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

    /// プロンプト再同期に成功し確認要求が無応答のまま、最後の受信から30秒に達したら猶予を待たずに終わります。
    ///
    /// 責務: 終了原因が車両応答なし、終了時刻が最後の受信、区間の再開が無いことを確認します(仕様 1)。
    func testPromptResyncSucceedsButProbeSilentEndsAtThirtySeconds() async {
        let (fixture, collector, lastReceived) = await probeSilent(recoveryResults: [true], elapsed: vehicleOff)

        await assertVehicleOff(fixture, collector, lastReceived: lastReceived)
        XCTAssertEqual(fixture.linkRecovery.calls, [.promptResync])
    }

    /// ATZ再初期化に成功し確認要求が無応答のまま、最後の受信から30秒に達したら猶予を待たずに終わります。
    ///
    /// 責務: プロンプト再同期が尽きた後の再初期化の成功でも、車両応答なしとして終わることを確認します(仕様 1)。
    func testReinitializeSucceedsButProbeSilentEndsAtThirtySeconds() async {
        let (fixture, collector, lastReceived) = await probeSilent(
            recoveryResults: [false, false, false, true],
            elapsed: vehicleOff
        )

        await assertVehicleOff(fixture, collector, lastReceived: lastReceived)
        XCTAssertEqual(fixture.linkRecovery.calls.last, .reinitializeFromReset)
    }

    /// 30秒を過ぎてから確認要求の無応答が確定した場合も、猶予を待たずに終わります。
    ///
    /// 責務: 30秒を大きく超えた(猶予3分以内の)経過でも、車両応答なしで終わることを確認します(仕様 1)。
    func testProbeSilentWellPastThirtySecondsEnds() async {
        let (fixture, collector, lastReceived) = await probeSilent(recoveryResults: [true], elapsed: vehicleOff * 3)

        await assertVehicleOff(fixture, collector, lastReceived: lastReceived)
    }

    /// 30秒の1ナノ秒前の無応答では終わらず、回復を続けます。
    ///
    /// 責務: 境界の直前は車両応答なしとみなさず、次の回復試行へ進み、終了しないことを確認します(仕様 1)。
    func testProbeSilentJustBeforeThirtySecondsKeepsRecovering() async {
        let (fixture, collector, _) = await probeSilent(recoveryResults: [true], elapsed: vehicleOff - 1)

        await fixture.linkRecovery.waitForCalls(2)

        XCTAssertGreaterThanOrEqual(fixture.linkRecovery.calls.count, 2, "次の回復試行へ進む")
        XCTAssertNil(collector.termination)
    }

    /// リンク断では、アダプターが応答しても30秒では終わらず、3分の猶予まで待ちます。
    ///
    /// 責務: 通信失敗の途切れは車両応答なしとみなさず、猶予切れで接続断として終わることを確認します(仕様 2)。
    func testLinkLostKeepsThreeMinuteGraceEvenWhenAdapterResponds() async {
        let fixture = make()
        fixture.linkRecovery.schedule([true])
        fixture.dates.set(lastReceivedAt)
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: .linkLost)
        await fixture.waitForSentRequests(3)
        fixture.dates.set(laterDate)
        fixture.advanceClock(to: lastReceived + vehicleOff * 2)
        await fixture.telemetry.release(.timedOut)

        await fixture.waitForPause(of: collector)
        XCTAssertNil(collector.termination, "30秒を過ぎても3分までは終わらない")
        fixture.advanceClock(to: lastReceived + grace + 1)
        await fixture.deadlineWaiter.waitForPending(lastReceived + grace + 1)
        fixture.deadlineWaiter.release(deadline: lastReceived + grace + 1)

        await fixture.assertExpired(
            collector, cause: .linkLost, lastReceivedAt: lastReceivedAt, segmentEndReason: .linkLost, sessionEndReason: .connectionLost
        )
    }

    /// アダプター自体が応答しない応答途絶では、30秒では終わらず、3分の猶予を待ちます。
    ///
    /// 責務: 回復操作がすべて失敗する場合は車両応答なしとみなさず、猶予切れで終わることを確認します(仕様 2)。
    func testUnresponsiveAdapterKeepsThreeMinuteGrace() async {
        let fixture = make()
        fixture.dates.set(lastReceivedAt)
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: .responseStall)
        fixture.dates.set(laterDate)
        fixture.advanceClock(to: lastReceived + vehicleOff * 2)

        await fixture.waitForPause(of: collector)
        XCTAssertNil(collector.termination, "アダプターが応答しない間は3分まで終わらない")
        fixture.advanceClock(to: lastReceived + grace + 1)
        await fixture.deadlineWaiter.waitForPending(lastReceived + grace + 1)
        fixture.deadlineWaiter.release(deadline: lastReceived + grace + 1)

        await fixture.assertExpired(
            collector, cause: .responseStall, lastReceivedAt: lastReceivedAt, segmentEndReason: .responseStall,
            sessionEndReason: .vehicleNoResponse
        )
    }

    /// 応答途絶のあと回復でアダプターが応答し、確認要求の無応答が指定の経過で確定した状態まで進めます。
    ///
    /// 責務: 回復操作の結果を予約し、確認要求(3件目の送信)の応答待ちの間に単調時計を進めてから無応答にします。
    /// - Parameters:
    ///   - recoveryResults: 回復操作が返す結果の予約。
    ///   - elapsed: 確認要求の無応答が確定する時点の、最後の受信からの経過(ナノ秒)。
    /// - Returns: ループ部品、購読、最後の正応答を受けた時点の単調時計の値。
    private func probeSilent(
        recoveryResults: [Bool],
        elapsed: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> (LiveTelemetryAcquisitionLoopFixture, LiveTelemetryAcquisitionEventCollector, UInt64) {
        let fixture = make()
        fixture.linkRecovery.schedule(recoveryResults)
        fixture.dates.set(lastReceivedAt)
        let (collector, lastReceived) = await fixture.startAndInterrupt(cause: .responseStall, file: file, line: line)
        await fixture.waitForSentRequests(3, file: file, line: line)
        fixture.dates.set(laterDate)
        fixture.advanceClock(to: lastReceived + elapsed, file: file, line: line)
        await fixture.telemetry.release(.timedOut, file: file, line: line)
        return (fixture, collector, lastReceived)
    }

    /// 猶予の期限を待たずに、車両応答なしで終わったことを検証します。
    ///
    /// 責務: 期限待ちを解放せずに終了し、終了原因・終了時刻・区間の扱いが仕様のリテラルと一致することを確認します。
    /// - Parameters:
    ///   - fixture: ループ部品。
    ///   - collector: 確認する購読。
    ///   - lastReceived: 最後の正応答を受けた時点の単調時計の値。
    private func assertVehicleOff(
        _ fixture: LiveTelemetryAcquisitionLoopFixture,
        _ collector: LiveTelemetryAcquisitionEventCollector,
        lastReceived: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let termination = await fixture.waitForTermination(of: collector, file: file, line: line)

        XCTAssertEqual(termination?.sessionEndReason, .vehicleNoResponse, file: file, line: line)
        XCTAssertEqual(termination?.sessionEndedAt, lastReceivedAt, "終了時刻は最後に受信した時刻", file: file, line: line)
        let segments = fixture.recorder?.segmentCalls ?? []
        XCTAssertEqual(segments, [
            .endSegment(generation: 1, reason: .responseStall, lastReceivedAt: lastReceivedAt)
        ], "区間は再開されない", file: file, line: line)
        let finishes = fixture.recorder?.finishCalls ?? []
        XCTAssertEqual(finishes, [.finish(generation: 1, reason: .vehicleNoResponse)], file: file, line: line)
        XCTAssertFalse(fixture.deadlineWaiter.pendingDeadlines.contains(lastReceived + grace + 1), "3分の期限待ちに入らない", file: file, line: line)
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
