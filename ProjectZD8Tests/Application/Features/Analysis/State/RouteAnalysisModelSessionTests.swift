import Foundation
import XCTest
@testable import ProjectZD8

/// 解析の走行ルートのモデルで、同じセッションの再表示・アカウントの変化・契約外の失敗の扱いを検証します。
@MainActor
final class RouteAnalysisModelSessionTests: XCTestCase {
    private typealias Values = RouteAnalysisModelTestValues

    /// モデルと部品の組です。
    private var harness = RouteAnalysisModelHarness()

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.port.gate.releaseAll()
        try await super.tearDown()
    }

    /// 責務: 読み込み済みの同じセッションを再び表示しても、読み直さないことを確かめます。
    func testReshowingReadySessionDoesNotReload() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)

        harness.model.send(.sessionShown(session))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.port.calls.count, 1)
        XCTAssertEqual(harness.state.phase, .ready)
    }

    /// 責務: 読み込み中の同じセッションを再び表示しても、読み込みを増やさないことを確かめます。
    func testReshowingLoadingSessionDoesNotReload() async {
        let session = DrivingRouteTestValues.session()
        harness.setResult(.available(Values.route(pointCount: 4), noticeKeys: []), for: session)
        harness.port.gate.hold(session.id)
        harness.model.send(.accountIdentifierChanged(Values.account))
        harness.model.send(.sessionShown(session))
        await harness.waitForGateWaiting(1)

        harness.model.send(.sessionShown(session))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.port.calls.count, 1)
        XCTAssertEqual(harness.state.phase, .loading)
    }

    /// 責務: 空文字のアカウントはアカウントなしとして扱い、表示してもアカウント待ちのまま読み込まないことを確かめます。
    func testEmptyAccountIsTreatedAsMissing() async {
        let session = DrivingRouteTestValues.session()

        harness.model.send(.accountIdentifierChanged(""))
        harness.model.send(.sessionShown(session))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.state.phase, .waitingForAccount)
        XCTAssertEqual(harness.port.calls, [])
    }

    /// 責務: 同じアカウントを再び受け取っても、読み直さないことを確かめます。
    func testSameAccountDoesNotReload() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)

        harness.model.send(.accountIdentifierChanged(Values.account))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.port.calls.count, 1)
    }

    /// 責務: アカウントが別の値へ変わると、新しいアカウントで読み直し、前に受け取った時系列を捨てることを確かめます。
    func testAccountChangeReloadsAndDiscardsTimeline() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)
        harness.model.send(.timelineLoaded(session.id, Values.speedSamples()))
        await harness.waitUntil("colored") { self.harness.state.selectedColorSource == .metric(.vehicleSpeed) }

        harness.model.send(.accountIdentifierChanged("other-account"))

        await harness.waitForCallCount(2)
        await harness.waitUntil("ready again") {
            self.harness.state.phase == .ready && self.harness.state.layers != nil && self.harness.state.selectedColorSource == nil
        }
        XCTAssertEqual(harness.port.calls.last?.accountIdentifier, "other-account")
        XCTAssertTrue(harness.state.colorSourceOptions.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(harness.lineCategories, [.base])
    }

    /// 責務: ポートが取り消し以外の失敗を投げたら、再試行できる失敗(空でない文言キー)になることを確かめます。
    func testThrownFailureBecomesRetryableFailure() async {
        let session = DrivingRouteTestValues.session()
        harness.port.errors[session.id] = URLError(.notConnectedToInternet)
        harness.model.send(.accountIdentifierChanged(Values.account))

        harness.model.send(.sessionShown(session))

        await harness.waitUntil("failed") { if case .failed = self.harness.state.phase { true } else { false } }
        guard case .failed(let messageKey, let isRetryable) = harness.state.phase else {
            return XCTFail("失敗の状態になっていません: \(harness.state.phase)")
        }
        XCTAssertFalse(messageKey.isEmpty)
        XCTAssertTrue(isRetryable)
    }
}
