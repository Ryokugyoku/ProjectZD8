import Foundation
import XCTest
@testable import ProjectZD8

/// 古い評価の結果が、セッションの切り替え・raw の変化・待ちへの後退・閉じた後に届いても反映されないこと(取消と世代の照合)を検証します
/// (設計書 §6.3・§7 TC3)。
///
/// 順序はポートの Fake を `RoadRegulationTestGate` で止めて作り、固定時間の sleep に頼りません。
/// `ignoresCancellation` の呼び出しは取消に応じず、門が開いてから結果を返します(世代の照合を確かめるため)。
@MainActor
final class SessionRoadRegulationReviewModelStaleResultTests: XCTestCase {
    private typealias Values = SessionRoadRegulationReviewModelTestValues

    /// モデルと部品の組です。
    private var harness = SessionRoadRegulationReviewModelHarness()

    /// 責務: 止めた呼び出しを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.openAllGates()
        try await super.tearDown()
    }

    /// 責務: 標準の結果を返す呼び出しを門で止め、`ready(raw)` を送って門の前で待つまで待ちます。
    /// - Parameters:
    ///   - raw: Raw の所在。
    ///   - ignoresCancellation: 取消に応じずに結果を返すか。
    /// - Returns: 止めた門。
    private func startHeldEvaluation(
        raw: SessionRoadRegulationRawLogAvailability = .onDevice,
        ignoresCancellation: Bool = true
    ) async -> RoadRegulationTestGate? {
        let gate = harness.enqueue(.success(.reviewed(Values.standardReview())), held: true, ignoresCancellation: ignoresCancellation)
        harness.sendReadiness(.ready(raw))
        await harness.waitForWaiting(on: gate)
        return gate
    }

    /// 責務: 止めた1回目の呼び出しを再開し、結果を返し終えるまで待ってから、遅れた反映が起き得る間だけ待ちます。
    private func releaseFirstCall(_ gate: RoadRegulationTestGate?) async {
        gate?.open()
        await harness.waitForCompletion(ofCall: 0)
        await harness.settle()
    }

    /// 責務: セッション A の評価中に B へ切り替え、B の結果の後に A の結果が届いても、B の結果のままであることを確かめます。
    func testResultOfPreviousSessionAfterSwitchingIsDiscarded() async {
        let gate = await startHeldEvaluation()
        let other = ConnectionSessionID()

        await harness.load(Values.stopOnlyReview(), raw: .onDevice, session: other)
        let stateOfOther = harness.state
        await releaseFirstCall(gate)

        XCTAssertEqual(harness.state, stateOfOther)
        XCTAssertEqual(stateOfOther.sessionID, other)
        XCTAssertEqual(stateOfOther.summaries.map(\.total), [0, 1, 0, 0])
        XCTAssertEqual(harness.port.cancelledCalls, [0])
    }

    /// 責務: ready(.inCloud) の評価中に ready(.onDevice) が来ると、1回目が取消を受け、state は2回目の結果になることを確かめます。
    func testRawLogChangeCancelsFirstEvaluation() async {
        _ = await startHeldEvaluation(raw: .inCloud, ignoresCancellation: false)
        harness.enqueue(.success(.reviewed(Values.standardReview(hasVehicleSpeed: false))))

        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForCancellation(ofCall: 0)
        await harness.waitForCompletion(ofCall: 1)
        await harness.waitForStatus(.loaded)

        XCTAssertEqual(harness.port.calls.count, 2)
        XCTAssertEqual(harness.state.notices, [.speedNotRecorded, .unregulatedExplained])
    }

    /// 責務: raw が変わった後、取消に応じない1回目の結果が遅れて届いても、2回目の結果のままであることを確かめます。
    func testLateResultAfterRawLogChangeIsDiscarded() async {
        let gate = await startHeldEvaluation(raw: .inCloud)
        harness.enqueue(.success(.reviewed(Values.stopOnlyReview())))
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForCompletion(ofCall: 1)
        await harness.waitForStatus(.loaded)
        let stateOfSecond = harness.state

        await releaseFirstCall(gate)

        XCTAssertEqual(harness.state, stateOfSecond)
        XCTAssertEqual(stateOfSecond.summaries.map(\.total), [0, 1, 0, 0])
    }

    /// 責務: 評価中に待ちの段階へ戻ると、後から結果が届いても待ちの段階のまま・内容なしであることを確かめます。
    func testLateResultAfterFallingBackToWaitingIsDiscarded() async {
        let gate = await startHeldEvaluation()

        harness.sendReadiness(.waitingForRawLog)
        await releaseFirstCall(gate)

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState(sessionID: harness.sessionID, status: .waitingForRawLog))
        XCTAssertEqual(harness.port.cancelledCalls, [0])
    }

    /// 責務: 評価中に待ちの段階へ戻った後、古い世代のエラーが届いても failed にしないことを確かめます。
    func testLateErrorOfOldGenerationIsDiscarded() async {
        let gate = harness.enqueue(.failure(URLError(.cannotOpenFile)), held: true, ignoresCancellation: true)
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)

        harness.sendReadiness(.waitingForRoute)
        await releaseFirstCall(gate)

        XCTAssertEqual(harness.state.status, .waitingForRoute)
    }

    /// 責務: 評価中に閉じると取消され、state は初期(sessionID も nil)になり、遅れて届いても変わらないことを確かめます。
    func testDismissDuringEvaluationCancelsAndDiscardsLateResult() async {
        let gate = await startHeldEvaluation()

        harness.send(.dismissed)
        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
        await releaseFirstCall(gate)

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
        XCTAssertEqual(harness.port.cancelledCalls, [0])
    }

    /// 責務: 閉じた後に同じセッション・同じ raw の ready が来れば評価し直すことを確かめます。
    func testReadyAfterDismissIsEvaluatedAgain() async {
        await harness.load()
        harness.send(.dismissed)
        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())

        await harness.load()

        XCTAssertEqual(harness.port.calls.count, 2)
        XCTAssertEqual(harness.state.sessionID, harness.sessionID)
    }

    /// 責務: ポートが `CancellationError` を投げた時は state を変えない(evaluating のまま)ことを確かめます。
    func testCancellationErrorFromPortLeavesStateUnchanged() async {
        harness.enqueue(.failure(CancellationError()))

        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForCompletion(ofCall: 0)
        await harness.settle()

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState(sessionID: harness.sessionID, status: .evaluating))
    }
}
