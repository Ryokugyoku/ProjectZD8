import Foundation
import XCTest
@testable import ProjectZD8

/// 交通規制の照合のモデルが、アカウントの切り替えで評価を取り消して初期に戻り、同じ値(空文字は nil)では何もしないことを検証します
/// (設計書 §6.2・§6.5・§7 TC3 (d))。
@MainActor
final class SessionRoadRegulationReviewModelAccountTests: XCTestCase {
    private typealias Values = SessionRoadRegulationReviewModelTestValues

    /// モデルと部品の組です。
    private var harness = SessionRoadRegulationReviewModelHarness()

    /// 責務: 止めた呼び出しを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.openAllGates()
        try await super.tearDown()
    }

    /// 責務: 評価中に別のアカウントへ切り替えると取消され、state は初期になり、遅れて届いても変わらないことを確かめます。
    func testAccountChangeDuringEvaluationCancelsAndDiscardsLateResult() async {
        harness.send(.accountIdentifierChanged("account-a"))
        let gate = harness.enqueue(.success(.reviewed(Values.standardReview())), held: true, ignoresCancellation: true)
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)

        harness.send(.accountIdentifierChanged("account-b"))
        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
        gate?.open()
        await harness.waitForCompletion(ofCall: 0)
        await harness.settle()

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
        XCTAssertEqual(harness.port.cancelledCalls, [0])
    }

    /// 責務: 評価中のアカウントの切り替えで、取消に応じるポートは `CancellationError` を受けることを確かめます。
    func testAccountChangeCancelsPortCall() async {
        let gate = harness.enqueue(.success(.reviewed(Values.standardReview())), held: true)
        harness.sendReadiness(.ready(.onDevice))
        await harness.waitForWaiting(on: gate)

        harness.send(.accountIdentifierChanged("account-b"))
        await harness.waitForCancellation(ofCall: 0)
        await harness.settle()

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
        XCTAssertEqual(harness.port.completedCalls, [])
    }

    /// 責務: loaded の後に別のアカウントへ切り替えると、内容と重ね合わせが消えて初期になることを確かめます。
    func testAccountChangeAfterLoadedResetsState() async {
        harness.send(.accountIdentifierChanged("account-a"))
        await harness.load()

        harness.send(.accountIdentifierChanged("account-b"))

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
    }

    /// 責務: アカウントの切り替えの後に同じ readiness が送り直されると、評価し直すことを確かめます。
    func testReadyAfterAccountChangeIsEvaluatedAgain() async {
        harness.send(.accountIdentifierChanged("account-a"))
        await harness.load()
        harness.send(.accountIdentifierChanged("account-b"))

        await harness.load()

        XCTAssertEqual(harness.port.calls.count, 2)
        XCTAssertEqual(harness.state.status, .loaded)
    }

    /// 責務: 前と同じアカウントを送っても何もしない(loaded のまま・呼び直さない)ことを確かめます。
    func testSameAccountDoesNothing() async {
        harness.send(.accountIdentifierChanged("account-a"))
        await harness.load()
        harness.send(.rowSelected(1))
        let before = harness.state

        harness.send(.accountIdentifierChanged("account-a"))
        await harness.settle()

        XCTAssertEqual(harness.state, before)
        XCTAssertEqual(harness.port.calls.count, 1)
    }

    /// 責務: 初期値は nil なので、nil や空文字を送っても何もしない(空文字は nil とみなす)ことを確かめます。
    func testNilAndEmptyAccountAreSameAsInitial() async {
        await harness.load()
        let before = harness.state

        harness.send(.accountIdentifierChanged(""))
        harness.send(.accountIdentifierChanged(nil))
        await harness.settle()

        XCTAssertEqual(harness.state, before)
        XCTAssertEqual(harness.port.calls.count, 1)
    }

    /// 責務: サインイン中に空文字を送るとサインアウト(nil)とみなし、初期に戻ることを確かめます。
    func testEmptyAccountAfterSignedInResets() async {
        harness.send(.accountIdentifierChanged("account-a"))
        await harness.load()

        harness.send(.accountIdentifierChanged(""))

        XCTAssertEqual(harness.state, SessionRoadRegulationReviewState())
    }
}
