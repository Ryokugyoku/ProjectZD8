import Foundation
import XCTest
@testable import ProjectZD8

/// 交通規制の照合のモデルが、readiness(ルートと Raw の段階)に応じて評価を始める・待つ・捨てることを検証します(設計書 §6.1・§6.2・§7 TC3)。
@MainActor
final class SessionRoadRegulationReviewModelReadinessTests: XCTestCase {
    private typealias Values = SessionRoadRegulationReviewModelTestValues

    /// モデルと部品の組です。
    private var harness = SessionRoadRegulationReviewModelHarness()

    /// 責務: 止めた呼び出しを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.openAllGates()
        try await super.tearDown()
    }

    /// 責務: 作った直後は初期の状態(idle・内容なし・絞り込みは attention)であることを確かめます。
    func testInitialStateIsIdle() {
        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
        XCTAssertEqual(harness.state.status, .idle)
        XCTAssertEqual(harness.state.filter, .attention)
        XCTAssertNil(harness.state.sessionID)
    }

    /// 責務: 待ちの3段階では、ポートを呼ばずに同名の status になり、セッション ID を持つことを確かめます。
    func testWaitingReadinessDoesNotCallPortAndMirrorsStatus() async {
        let cases: [(SessionRoadRegulationReviewReadiness, SessionRoadRegulationReviewStatus)] = [
            (.waitingForRoute, .waitingForRoute), (.routeUnavailable, .routeUnavailable), (.waitingForRawLog, .waitingForRawLog),
        ]
        for (readiness, status) in cases {
            harness.sendReadiness(readiness)
            await harness.settle()

            XCTAssertEqual(harness.state.status, status, "\(readiness)")
            XCTAssertEqual(harness.state.sessionID, harness.sessionID, "\(readiness)")
            XCTAssertEqual(harness.port.calls, [], "\(readiness)")
        }
    }

    /// 責務: ready(.onDevice) でポートを1回(そのセッションで)呼び、evaluating を経て loaded になることを確かめます。
    func testReadyCallsPortOnceAndGoesThroughEvaluatingToLoaded() async {
        let gate = harness.enqueue(.success(.reviewed(Values.standardReview())), held: true)

        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)

        XCTAssertEqual(harness.state.status, .evaluating)
        XCTAssertEqual(harness.state.summaries, [])
        XCTAssertEqual(harness.state.overlays, [])
        XCTAssertEqual(harness.port.calls, [harness.sessionID])
        gate?.open()
        await harness.waitForStatus(.loaded)
        XCTAssertEqual(harness.port.calls.count, 1)
    }

    /// 責務: サインインしていなくても(アカウント nil のまま)評価することを確かめます。
    func testEvaluatesWithoutAccount() async {
        await harness.load()

        XCTAssertEqual(harness.state.status, .loaded)
        XCTAssertEqual(harness.port.calls.count, 1)
    }

    /// 責務: 同じ readiness を評価中と loaded の後に送っても、呼び出しは1回のままであることを確かめます。
    func testSameReadyIsNotEvaluatedTwice() async {
        let gate = harness.enqueue(.success(.reviewed(Values.standardReview())), held: true)
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)

        harness.sendReadiness(.ready(.onDevice))
        gate?.open()
        await harness.waitForStatus(.loaded)
        harness.sendReadiness(.ready(.onDevice))
        await harness.settle()

        XCTAssertEqual(harness.port.calls.count, 1)
        XCTAssertEqual(harness.state.status, .loaded)
    }

    /// 責務: 同じ ready(raw) は、結果が noTrack・noRegulationData・failed の時も呼び直さないことを確かめます。
    func testSameReadyAfterSettledResultsDoesNotCallAgain() async {
        let results: [(Result<SessionRoadRegulationReviewResult, any Error>, SessionRoadRegulationReviewStatus)] = [
            (.success(.noTrack), .noTrack), (.success(.noRegulationData), .noRegulationData), (.failure(URLError(.badURL)), .failed),
        ]
        for (result, status) in results {
            let harness = SessionRoadRegulationReviewModelHarness()
            harness.enqueue(result)
            harness.sendReadiness(.ready(.inCloud))
            await harness.waitForStatus(status)

            harness.sendReadiness(.ready(.inCloud))
            await harness.settle()

            XCTAssertEqual(harness.port.calls.count, 1, "\(status)")
            XCTAssertEqual(harness.state.status, status)
        }
    }

    /// 責務: ready(.inCloud) で loaded の後に ready(.onDevice) が来ると、2回目を呼び直すことを確かめます。
    func testChangedRawLogIsEvaluatedAgain() async {
        await harness.load(raw: .inCloud)

        await harness.load(Values.stopOnlyReview(), raw: .onDevice)

        XCTAssertEqual(harness.port.calls, [harness.sessionID, harness.sessionID])
        XCTAssertEqual(harness.state.summaries.map(\.total), [0, 1, 0, 0])
    }

    /// 責務: inCloud → waitingForRawLog → inCloud のように、待ちを挟んで同じ raw が来たら評価し直すことを確かめます。
    func testSameRawAfterWaitingIsEvaluatedAgain() async {
        await harness.load(raw: .inCloud)
        harness.sendReadiness(.waitingForRawLog)
        await harness.waitForStatus(.waitingForRawLog)

        await harness.load(raw: .inCloud)

        XCTAssertEqual(harness.port.calls.count, 2)
    }

    /// 責務: loaded 中に待ちの段階へ戻ると、内容・選択・重ね合わせが空、出典が `.empty` になり、絞り込みとセッションは残ることを確かめます。
    func testFallingBackToWaitingClearsContentButKeepsFilterAndSession() async {
        await harness.load()
        harness.send(.filterChanged(.all))
        harness.send(.rowSelected(0))
        XCTAssertEqual(harness.state.selectedRowID, 0)

        harness.sendReadiness(.waitingForRawLog)

        XCTAssertEqual(harness.state.status, .waitingForRawLog)
        XCTAssertEqual(harness.state.summaries, [])
        XCTAssertEqual(harness.state.sections, [])
        XCTAssertEqual(harness.state.notices, [])
        XCTAssertEqual(harness.state.overlays, [])
        XCTAssertNil(harness.state.selectedRowID)
        XCTAssertEqual(harness.state.attribution, .empty)
        XCTAssertEqual(harness.state.filter, .all)
        XCTAssertEqual(harness.state.sessionID, harness.sessionID)
    }

    /// 責務: 別のセッションの readiness で、セッション ID が変わり、絞り込みが attention・選択なし・内容なしに戻ることを確かめます。
    func testOtherSessionResetsToInitialStateOfThatSession() async {
        await harness.load()
        harness.send(.filterChanged(.all))
        harness.send(.rowSelected(0))
        let other = ConnectionSessionID()

        harness.sendReadiness(.waitingForRoute, session: other)

        let expected = SessionRoadRegulationReviewState(sessionID: other, status: .waitingForRoute)
        XCTAssertEqual(harness.state, expected)
    }

    /// 責務: 別のセッションで同じ raw の ready が来ても、そのセッションで評価し直すことを確かめます。
    func testOtherSessionWithSameRawIsEvaluated() async {
        await harness.load(raw: .onDevice)
        let other = ConnectionSessionID()

        await harness.load(Values.stopOnlyReview(), raw: .onDevice, session: other)

        XCTAssertEqual(harness.port.calls, [harness.sessionID, other])
        XCTAssertEqual(harness.state.sessionID, other)
    }
}
