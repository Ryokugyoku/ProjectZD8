import Foundation
import XCTest
@testable import ProjectZD8

/// 取得ループへ注入した「エンジン停止とみなす時間」(10秒・180秒)どおりに終わることを検証します。
///
/// 応答途絶のあと回復でアダプターは応答するのに確認要求が無応答のまま、最後の受信から設定秒数ちょうどで終わり(1ns前は続行)、
/// 終了原因は車両応答なし、終了時刻は最後の受信の実時刻です。時間は手動の単調時計と、テストが解放する確認要求の応答だけで進めます。
@MainActor
final class LiveTelemetryAcquisitionLoopVehicleOffDelayTests: XCTestCase {
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

    /// 10秒の設定では、最後の受信から10秒ちょうどで車両応答なしとして終わります。
    ///
    /// 責務: 終了原因・終了時刻・区間の再開なしを確認します。
    func testTenSecondDelayEndsAtTenSeconds() async {
        let (fixture, collector, lastReceived) = await probeSilent(delay: .seconds10, elapsed: 10_000_000_000)

        await assertVehicleOff(fixture, collector, lastReceived: lastReceived, delay: .seconds10)
    }

    /// 10秒の設定でも、10秒の1ns前の無応答では終わらず回復を続けます。
    ///
    /// 責務: 境界の直前は終了せず、次の回復試行へ進むことを確認します。
    func testTenSecondDelayKeepsRecoveringJustBefore() async {
        let (fixture, collector, _) = await probeSilent(delay: .seconds10, elapsed: 10_000_000_000 - 1)

        await fixture.linkRecovery.waitForCalls(2)

        XCTAssertGreaterThanOrEqual(fixture.linkRecovery.calls.count, 2)
        XCTAssertNil(collector.termination)
    }

    /// 180秒の設定では、最後の受信から180秒ちょうどで終わります(3分猶予の+1ns待たない)。
    ///
    /// 責務: 3分と重なる設定でも、終了原因が車両応答なし・終了時刻が最後の受信で、3分の期限待ちを経ないことを確認します。
    func testOneEightySecondDelayEndsExactlyAtThreeMinutes() async {
        let (fixture, collector, lastReceived) = await probeSilent(delay: .seconds180, elapsed: grace)

        await assertVehicleOff(fixture, collector, lastReceived: lastReceived, delay: .seconds180)
    }

    /// 180秒の設定でも、180秒の1ns前の無応答では終わりません。
    ///
    /// 責務: 境界の直前は終了せず、次の回復試行へ進むことを確認します。
    func testOneEightySecondDelayKeepsRecoveringJustBefore() async {
        let (fixture, collector, _) = await probeSilent(delay: .seconds180, elapsed: grace - 1)

        await fixture.linkRecovery.waitForCalls(2)

        XCTAssertGreaterThanOrEqual(fixture.linkRecovery.calls.count, 2)
        XCTAssertNil(collector.termination)
    }

    /// 応答途絶のあと回復でアダプターが応答し、確認要求の無応答が指定の経過で確定した状態まで進めます。
    ///
    /// 責務: プロンプト再同期を成功させ、確認要求(3件目の送信)の応答待ちの間に単調時計を進めてから無応答にします。
    /// - Parameters:
    ///   - delay: ループへ注入するエンジン停止とみなす時間。
    ///   - elapsed: 確認要求の無応答が確定する時点の、最後の受信からの経過(ナノ秒)。
    /// - Returns: ループ部品、購読、最後の正応答を受けた時点の単調時計の値。
    private func probeSilent(
        delay: VehicleOffDetectionDelay,
        elapsed: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> (LiveTelemetryAcquisitionLoopFixture, LiveTelemetryAcquisitionEventCollector, UInt64) {
        let fixture = LiveTelemetryAcquisitionLoopFixture(vehicleOffDelay: delay)
        self.fixture = fixture
        fixture.linkRecovery.schedule([true])
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
    ///   - delay: 注入した設定。3分(+1ns)の期限待ちに入っていないことの確認に使います。
    private func assertVehicleOff(
        _ fixture: LiveTelemetryAcquisitionLoopFixture,
        _ collector: LiveTelemetryAcquisitionEventCollector,
        lastReceived: UInt64,
        delay: VehicleOffDetectionDelay,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let termination = await fixture.waitForTermination(of: collector, file: file, line: line)

        XCTAssertEqual(termination?.sessionEndReason, .vehicleNoResponse, "\(delay)", file: file, line: line)
        XCTAssertEqual(termination?.sessionEndedAt, lastReceivedAt, "終了時刻は最後に受信した時刻", file: file, line: line)
        XCTAssertEqual(fixture.recorder?.segmentCalls, [
            .endSegment(generation: 1, reason: .responseStall, lastReceivedAt: lastReceivedAt)
        ], "区間は再開されない", file: file, line: line)
        XCTAssertEqual(fixture.recorder?.finishCalls, [.finish(generation: 1, reason: .vehicleNoResponse)], file: file, line: line)
        XCTAssertFalse(
            fixture.deadlineWaiter.pendingDeadlines.contains(lastReceived + grace + 1),
            "3分の期限待ちに入らない", file: file, line: line
        )
    }
}
