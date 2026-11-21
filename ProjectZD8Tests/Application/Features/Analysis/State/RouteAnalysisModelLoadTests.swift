import Foundation
import XCTest
@testable import ProjectZD8

/// 解析の走行ルートのモデルの、読み込みの状態の変化(アカウント待ち・読み込み中・読み込み済み・理由・失敗と再試行・閉じる)を検証します。
@MainActor
final class RouteAnalysisModelLoadTests: XCTestCase {
    private typealias Values = RouteAnalysisModelTestValues

    /// モデルと部品の組です。
    private var harness = RouteAnalysisModelHarness()

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.port.gate.releaseAll()
        try await super.tearDown()
    }

    /// 責務: アカウントが無いまま表示するとアカウント待ちになり、読み込まないことを確かめます。
    func testShowingWithoutAccountWaits() async {
        let session = DrivingRouteTestValues.session()

        harness.model.send(.sessionShown(session))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.state.sessionID, session.id)
        XCTAssertEqual(harness.state.phase, .waitingForAccount)
        XCTAssertEqual(harness.port.calls, [])
    }

    /// 責務: アカウント待ちの後にアカウントが届くと、そのアカウントで読み込んで読み込み済みになることを確かめます。
    func testAccountArrivalStartsWaitingLoad() async {
        let session = DrivingRouteTestValues.session()
        harness.setResult(.available(Values.route(pointCount: 4), noticeKeys: []), for: session)
        harness.model.send(.sessionShown(session))

        harness.model.send(.accountIdentifierChanged(Values.account))

        await harness.waitUntil("ready") { self.harness.state.phase == .ready }
        XCTAssertEqual(harness.port.calls, [RouteAnalysisTrackPortFake.Call(sessionID: session.id, accountIdentifier: Values.account)])
    }

    /// 責務: 表示すると読み込み中になり、結果が届くと色なし(base)の線・標高のグラフ・読み込みの注記・選べない4指標を持つ読み込み済みになることを確かめます。
    func testShowingLoadsThenReadyWithoutColoring() async {
        let session = DrivingRouteTestValues.session()
        harness.setResult(.available(Values.route(pointCount: 6), noticeKeys: ["test.notice"]), for: session)
        harness.port.gate.hold(session.id)
        harness.model.send(.accountIdentifierChanged(Values.account))

        harness.model.send(.sessionShown(session))
        await harness.waitForGateWaiting(1)

        XCTAssertEqual(harness.state.phase, .loading)
        XCTAssertEqual(harness.state.sessionID, session.id)
        harness.port.gate.release(session.id)
        await harness.waitUntil("ready") { self.harness.state.phase == .ready && self.harness.state.layers != nil }
        XCTAssertFalse(harness.lineCategories.isEmpty)
        XCTAssertEqual(harness.lineCategories, [.base])
        XCTAssertEqual(harness.state.layers?.markers.count, 2)
        XCTAssertNotNil(harness.state.elevationChart)
        XCTAssertNil(harness.state.metricChart)
        XCTAssertNil(harness.state.selectedColorSource)
        XCTAssertEqual(harness.state.noticeKeys, ["test.notice"])
        XCTAssertEqual(harness.state.colorSourceOptions.count, RouteAnalysisColorMetric.allCases.count)
        XCTAssertTrue(harness.state.colorSourceOptions.allSatisfy { !$0.isEnabled })
    }

    /// 責務: ポートの「ルートなし」は、理由のキーと記号のまま `unavailable` になることを確かめます。
    func testUnavailableResultIsShownAsIs() async {
        let session = DrivingRouteTestValues.session()
        harness.setResult(.unavailable(reasonKey: "history.route.absence.not_in_cloud", systemImage: "icloud.slash"), for: session)
        harness.model.send(.accountIdentifierChanged(Values.account))

        harness.model.send(.sessionShown(session))

        let expected = RouteAnalysisLoadPhase.unavailable(reasonKey: "history.route.absence.not_in_cloud", systemImage: "icloud.slash")
        await harness.waitUntil("unavailable") { self.harness.state.phase == expected }
        XCTAssertNil(harness.state.layers)
    }

    /// 責務: ポートの失敗は、文言キーと再試行の可否のまま `failed` になることを確かめます。
    func testFailedResultIsShownAsIs() async {
        let session = DrivingRouteTestValues.session()
        harness.setResult(.failed(messageKey: "history.route.failure.update_required", isRetryable: false), for: session)
        harness.model.send(.accountIdentifierChanged(Values.account))

        harness.model.send(.sessionShown(session))

        let expected = RouteAnalysisLoadPhase.failed(messageKey: "history.route.failure.update_required", isRetryable: false)
        await harness.waitUntil("failed") { self.harness.state.phase == expected }
    }

    /// 責務: 再試行できる失敗の後の再試行で読み直し、読み込み済みになることを確かめます。
    func testRetryReloadsRetryableFailure() async {
        let session = DrivingRouteTestValues.session()
        harness.setResult(.failed(messageKey: "history.route.failure.load", isRetryable: true), for: session)
        harness.model.send(.accountIdentifierChanged(Values.account))
        harness.model.send(.sessionShown(session))
        await harness.waitUntil("failed") { if case .failed = self.harness.state.phase { true } else { false } }
        harness.setResult(.available(Values.route(pointCount: 4), noticeKeys: []), for: session)

        harness.model.send(.retryRequested)

        await harness.waitUntil("ready") { self.harness.state.phase == .ready && self.harness.state.layers != nil }
        XCTAssertEqual(harness.port.calls.count, 2)
    }

    /// 責務: 再試行できない失敗では、再試行を無視して読み直さないことを確かめます。
    func testRetryIgnoredForNonRetryableFailure() async {
        let session = DrivingRouteTestValues.session()
        let failure = RouteAnalysisLoadPhase.failed(messageKey: "history.route.failure.update_required", isRetryable: false)
        harness.setResult(.failed(messageKey: "history.route.failure.update_required", isRetryable: false), for: session)
        harness.model.send(.accountIdentifierChanged(Values.account))
        harness.model.send(.sessionShown(session))
        await harness.waitUntil("failed") { self.harness.state.phase == failure }

        harness.model.send(.retryRequested)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.port.calls.count, 1)
        XCTAssertEqual(harness.state.phase, failure)
    }

    /// 責務: ルートなしや読み込み済みの時は、再試行を無視して読み直さないことを確かめます。
    func testRetryIgnoredWhenNotFailed() async {
        let unavailable = DrivingRouteTestValues.session()
        harness.setResult(.unavailable(reasonKey: "history.route.absence.not_recorded", systemImage: "map"), for: unavailable)
        harness.model.send(.accountIdentifierChanged(Values.account))
        harness.model.send(.sessionShown(unavailable))
        await harness.waitUntil("unavailable") { if case .unavailable = self.harness.state.phase { true } else { false } }
        harness.model.send(.retryRequested)
        await LocationRecordingBoundedWaiter.settle()
        XCTAssertEqual(harness.port.calls.count, 1)

        let ready = DrivingRouteTestValues.session()
        await harness.showReadyRoute(ready)
        harness.model.send(.retryRequested)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.port.calls.count, 2)
        XCTAssertEqual(harness.state.phase, .ready)
    }

    /// 責務: 読み込み済みの後に閉じると、初期の状態へ戻ることを確かめます。
    func testDismissResetsState() async {
        let session = DrivingRouteTestValues.session()
        await harness.showReadyRoute(session)

        harness.model.send(.dismissed)

        await harness.waitUntil("reset") { self.harness.state == RouteAnalysisState() }
        await LocationRecordingBoundedWaiter.settle()
        XCTAssertEqual(harness.state, RouteAnalysisState())
    }
}
