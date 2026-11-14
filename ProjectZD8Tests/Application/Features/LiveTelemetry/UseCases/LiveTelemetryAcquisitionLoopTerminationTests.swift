import Foundation
import XCTest
@testable import ProjectZD8

/// 取得ループの無応答・接続断・停止・世代切替による終了を検証します。
@MainActor
final class LiveTelemetryAcquisitionLoopTerminationTests: XCTestCase {
    /// 各テストのループ部品です。
    private var fixture: LiveTelemetryAcquisitionLoopFixture?

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 2周目がまるごと無応答なら無応答で終わり、記録の終了とendSessionが呼ばれます。
    ///
    /// 責務: 正応答0件の周回を `noVehicleResponse` へ変換し、終了処理を1回ずつ行うことを確認します。
    func testRoundWithoutAnyResponseEndsAsNoVehicleResponse() async {
        let (fixture, collector) = await startTwoPIDLoop()
        await fixture.telemetry.answer(2) { _ in .responded([1]) }
        await fixture.telemetry.release(.timedOut)
        await fixture.telemetry.release(.unclassifiedResponse)

        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .noVehicleResponse)
        XCTAssertEqual(collector.events.last, .ended(.noVehicleResponse))
        XCTAssertEqual(fixture.telemetry.sentRequests.count, 4)
        XCTAssertEqual(fixture.telemetry.endSessionCount, 1)
        let finishes = await fixture.recorder?.finishCalls
        XCTAssertEqual(finishes, [.finish(generation: 1, reason: .vehicleNoResponse)])
    }

    /// 初回周回がまるごと無応答なら、取得対象を確定せずに無応答で終わります。
    ///
    /// 責務: 初回周回の正応答0件を `noVehicleResponse` へ変換し、取得対象の確定を流さないことを確認します。
    func testInitialRoundWithoutAnyResponseEndsBeforeTargetsAreConfirmed() async {
        let (fixture, collector) = await startTwoPIDLoop()
        await fixture.telemetry.answer(2) { _ in .timedOut }

        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .noVehicleResponse)
        XCTAssertTrue(collector.confirmedTargets.isEmpty)
        XCTAssertEqual(fixture.telemetry.endSessionCount, 1)
    }

    /// 正応答0件の周回に通信失敗があれば接続断で終わり、記録の終了とendSessionが呼ばれます。
    ///
    /// 責務: 通信境界の喪失を含む無応答周回を `connectionLost` へ変換することを確認します。
    func testRoundWithTransportFailureEndsAsConnectionLost() async {
        let (fixture, collector) = await startTwoPIDLoop()
        await fixture.telemetry.answer(2) { _ in .responded([1]) }
        await fixture.telemetry.release(.transportFailure)
        await fixture.telemetry.release(.timedOut)

        let termination = await fixture.waitForTermination(of: collector)

        XCTAssertEqual(termination, .connectionLost)
        XCTAssertEqual(fixture.telemetry.endSessionCount, 1)
        let finishes = await fixture.recorder?.finishCalls
        XCTAssertEqual(finishes, [.finish(generation: 1, reason: .connectionLost)])
    }

    /// 停止すると応答待ちの要求が取り消され、以後は要求が送られません。
    ///
    /// 責務: `stop` が停止理由を返し、終了処理を行い、2回目は動いていないことを返すことを確認します。
    func testStopEndsLoopAndNoFurtherRequestIsSent() async {
        let (fixture, collector) = await startTwoPIDLoop()
        await fixture.telemetry.answer(3) { _ in .responded([1]) }
        await fixture.waitForSentRequests(4)

        let termination = await fixture.loop.stop()
        await LiveTelemetryBoundedWaiter.settle(polls: 100)

        XCTAssertEqual(termination, .stopped)
        XCTAssertEqual(fixture.telemetry.sentRequests.count, 4)
        XCTAssertNil(fixture.telemetry.pendingRequest)
        XCTAssertEqual(fixture.telemetry.endSessionCount, 1)
        _ = await fixture.waitForTermination(of: collector)
        XCTAssertEqual(collector.termination, .stopped)
        let finishes = await fixture.recorder?.finishCalls
        XCTAssertEqual(finishes, [.finish(generation: 1, reason: .userDisconnected)])
        let secondStop = await fixture.loop.stop()
        XCTAssertNil(secondStop)
    }

    /// 新しい世代を開始すると前の世代が停止で終わり、以後の記録はすべて新しい世代になります。
    ///
    /// 責務: 前世代の終了処理が新世代の記録開始より先に行われ、前世代の購読へ終了後の出来事が流れないことを確認します。
    func testNewStartInvalidatesPreviousGeneration() async {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        let definitions = LiveTelemetryTestDefinitions.standard([0x0C, 0x0D])
        let first = await fixture.start(generation: 1, definitions: definitions)
        await fixture.waitForSentRequests(1)

        let second = await fixture.start(generation: 2, definitions: definitions)
        let firstTermination = await fixture.waitForTermination(of: first)
        await fixture.telemetry.answer(3) { _ in .responded([5]) }
        await fixture.waitForSentRequests(5)

        XCTAssertEqual(firstTermination, .stopped)
        XCTAssertEqual(first.events.last, .ended(.stopped))
        XCTAssertTrue(first.samples.isEmpty)
        XCTAssertEqual(second.samples.count, 3)
        let calls = await fixture.recorder?.calls ?? []
        let firstFinish = calls.firstIndex(of: .finish(generation: 1, reason: .userDisconnected))
        let secondStart = calls.firstIndex(of: .start(generation: 2))
        XCTAssertNotNil(firstFinish)
        XCTAssertNotNil(secondStart)
        XCTAssertLessThan(firstFinish ?? .max, secondStart ?? .min)
        let laterRecords = calls.suffix(from: secondStart ?? calls.endIndex).compactMap {
            if case let .record(result) = $0 { result.generation } else { nil }
        }
        XCTAssertEqual(laterRecords, [2, 2, 2])
    }

    /// 2PIDの取得を始めます。
    ///
    /// 責務: 高優先2PIDを取得対象にしたループを開始し、部品と購読を返します。
    /// - Returns: ループ部品と購読。
    private func startTwoPIDLoop() async -> (LiveTelemetryAcquisitionLoopFixture, LiveTelemetryAcquisitionEventCollector) {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        let collector = await fixture.start(definitions: LiveTelemetryTestDefinitions.standard([0x0C, 0x0D]))
        return (fixture, collector)
    }
}
