import Foundation
import XCTest
@testable import ProjectZD8

/// 古い読み込みの結果が、別のセッションへの切り替えや閉じた後に届いても反映されないこと(取り消しと世代の照合)を検証します。
///
/// ポートの Fake は取り消しに応じず、門で止めた読み込みは再開まで待ってから結果を返します。固定時間の sleep に頼らず、
/// 門の再開と完了の記録で順序を決めます。
@MainActor
final class RouteAnalysisModelStaleResultTests: XCTestCase {
    private typealias Values = RouteAnalysisModelTestValues

    /// モデルと部品の組です。
    private var harness = RouteAnalysisModelHarness()

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.port.gate.releaseAll()
        try await super.tearDown()
    }

    /// 線の点の合計です。
    private var drawnPointCount: Int {
        harness.state.layers?.lines.reduce(0) { $0 + $1.coordinates.count } ?? 0
    }

    /// 前のセッションの読み込みを門で止めたまま表示します。
    ///
    /// 責務: アカウントを渡し、前のセッションの結果(点 8)を置いて表示し、門で止まるまで待ちます。
    /// - Parameter previous: 前のセッション。
    private func showHeldPrevious(_ previous: ConnectionSession) async {
        harness.setResult(.available(Values.route(pointCount: 8), noticeKeys: ["test.previous"]), for: previous)
        harness.port.gate.hold(previous.id)
        harness.model.send(.accountIdentifierChanged(Values.account))
        harness.model.send(.sessionShown(previous))
        await harness.waitForGateWaiting(1)
    }

    /// 責務: 新しいセッションの読み込み済みの後に前のセッションの結果が届いても、新しいセッションの内容のままであることを確かめます。
    func testStaleResultAfterSwitchingIsDiscarded() async throws {
        let previous = DrivingRouteTestValues.session()
        let next = DrivingRouteTestValues.session()
        await showHeldPrevious(previous)
        harness.setResult(.available(Values.route(pointCount: 3), noticeKeys: []), for: next)

        harness.model.send(.sessionShown(next))
        await harness.waitUntil("next ready") { self.harness.state.sessionID == next.id && self.harness.state.phase == .ready && self.drawnPointCount == 3 }
        harness.port.gate.release(previous.id)
        _ = try await harness.waitForCompletion(of: previous)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.state.sessionID, next.id)
        XCTAssertEqual(harness.state.phase, .ready)
        XCTAssertEqual(drawnPointCount, 3)
        XCTAssertFalse(harness.state.noticeKeys.contains("test.previous"))
    }

    /// 責務: 新しいセッションの読み込み中に前のセッションの結果が届いても、新しいセッションの読み込み中のままであることを確かめます。
    func testStaleResultWhileNextIsLoadingIsDiscarded() async throws {
        let previous = DrivingRouteTestValues.session()
        let next = DrivingRouteTestValues.session()
        await showHeldPrevious(previous)
        harness.setResult(.available(Values.route(pointCount: 3), noticeKeys: []), for: next)
        harness.port.gate.hold(next.id)

        harness.model.send(.sessionShown(next))
        await harness.waitForGateWaiting(2)
        harness.port.gate.release(previous.id)
        _ = try await harness.waitForCompletion(of: previous)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.state.sessionID, next.id)
        XCTAssertEqual(harness.state.phase, .loading)
        XCTAssertNil(harness.state.layers)
        harness.port.gate.release(next.id)
        await harness.waitUntil("next ready") { self.harness.state.phase == .ready && self.drawnPointCount == 3 }
    }

    /// 責務: 読み込み中に閉じると読み込みを取り消し、後から結果が届いても初期の状態のままであることを確かめます。
    func testDismissCancelsLoadAndDiscardsLateResult() async throws {
        let session = DrivingRouteTestValues.session()
        await showHeldPrevious(session)

        harness.model.send(.dismissed)
        await harness.waitUntil("reset") { self.harness.state == RouteAnalysisState() }
        harness.port.gate.release(session.id)
        let completion = try await harness.waitForCompletion(of: session)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(completion.wasCancelled)
        XCTAssertEqual(harness.state, RouteAnalysisState())
    }

    /// 責務: 前のセッションの時系列が切り替えの後に届いても、新しいセッションの色分けに使わないことを確かめます。
    func testTimelineOfPreviousSessionAfterSwitchingIsIgnored() async {
        let previous = DrivingRouteTestValues.session()
        let next = DrivingRouteTestValues.session()
        await harness.showReadyRoute(previous)
        await harness.showReadyRoute(next)

        harness.model.send(.timelineLoaded(previous.id, Values.speedSamples()))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.state.sessionID, next.id)
        XCTAssertNil(harness.state.selectedColorSource)
        XCTAssertEqual(harness.lineCategories, [.base])
    }
}
