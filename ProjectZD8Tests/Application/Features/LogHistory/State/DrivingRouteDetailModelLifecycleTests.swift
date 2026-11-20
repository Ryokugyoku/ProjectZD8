import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの詳細のモデルの、セッションの切り替え・再表示・アカウントの変化・閉じた時の取消を検証します。
///
/// 前の読み込みは門で止めて遅らせます。止めたまま終わらないよう、tearDown で必ず再開します。
@MainActor
final class DrivingRouteDetailModelLifecycleTests: XCTestCase {
    /// モデルと部品の組です。
    private var harness = DrivingRouteDetailModelHarness()

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.gate.releaseAll()
        try await super.tearDown()
    }

    /// 別のセッションへ切り替えた後に前の読み込みが終わっても、前の結果で上書きしません。
    ///
    /// 責務: 前のセッションの読み込みを止めたまま次を表示し、次の内容が出た後に前を再開しても、次の内容のままで、前の読み込みが取り消されていることを確認します。
    func testSwitchingSessionDiscardsPreviousResult() async throws {
        let previous = DrivingRouteTestValues.session()
        let next = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: previous.id, sampleCount: 5))
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: next.id, sampleCount: 3))
        harness.gate.hold(previous.id)
        showWithAccount(previous)
        await harness.waitForGateWaiting(1)

        harness.model.send(.sessionShown(next))
        let nextContent = try await harness.waitForLoadedContent(next.id)
        harness.gate.release(previous.id)
        let resumption = try await harness.waitForResumption(previous.id)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(resumption.wasCancelled)
        XCTAssertEqual(harness.model.state.sessionID, next.id)
        XCTAssertEqual(harness.loadedContent, nextContent)
        XCTAssertEqual(nextContent.geometry.polylines.first?.coordinates.count, 3)
    }

    /// 終了済みで読み込み済みのセッションを再表示しても、読み直しません。
    ///
    /// 責務: 同じ終了済みのセッションの2回目の表示で、読み込みが1回のまま内容が変わらないことを確認します。
    func testEndedLoadedSessionIsNotReloaded() async throws {
        let session = DrivingRouteTestValues.session(hasEnded: true)
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        showWithAccount(session)
        let content = try await harness.waitForLoadedContent(session.id)

        harness.model.send(.sessionShown(session))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.recorder.calls.count, 1)
        XCTAssertEqual(harness.loadedContent, content)
    }

    /// 読み込み中に同じセッションがもう一度開かれたら、終了済みでも読み直します。
    ///
    /// 責務: 1回目の読み込みを止めたまま再表示すると2回目が呼ばれ、1回目は取り消され、2回目の結果が出ることを確認します。
    func testReshowWhileLoadingReloadsEvenWhenEnded() async throws {
        let session = DrivingRouteTestValues.session(hasEnded: true)
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        harness.gate.hold(session.id)
        showWithAccount(session)
        await harness.waitForGateWaiting(1)

        harness.model.send(.sessionShown(session))
        await harness.waitForGateWaiting(2)
        harness.gate.release(session.id)

        _ = try await harness.waitForLoadedContent(session.id)
        XCTAssertEqual(harness.recorder.calls.map(\.sessionID), [session.id, session.id])
        await LocationRecordingBoundedWaiter.waitUntil("2 resumptions") { self.harness.recorder.resumptions.count == 2 }
        XCTAssertEqual(harness.recorder.resumptions.map(\.wasCancelled).sorted { !$0 && $1 }, [false, true])
    }

    /// 進行中のセッションは、再表示のたびに読み直します。
    ///
    /// 責務: 終了していないセッションの2回目の表示で、2回目の読み込みが呼ばれ、内容が出ることを確認します。
    func testInProgressSessionIsReloadedOnEachShow() async throws {
        let session = DrivingRouteTestValues.session(hasEnded: false)
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        showWithAccount(session)
        _ = try await harness.waitForLoadedContent(session.id)

        harness.model.send(.sessionShown(session))
        await harness.waitForCallCount(2)

        _ = try await harness.waitForLoadedContent(session.id)
        XCTAssertEqual(harness.recorder.calls.map(\.sessionID), [session.id, session.id])
    }

    /// アカウントが変わったら、内容を捨て、表示中のセッションを新しいアカウントで読み直します。
    ///
    /// 責務: 別のアカウントへの変化で、読み込み中(内容なし)になり、新しいアカウントで読み込みが呼ばれることを確認します。
    func testAccountChangeDiscardsContentAndReloadsWithNewAccount() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        showWithAccount(session)
        _ = try await harness.waitForLoadedContent(session.id)
        harness.gate.hold(session.id)

        harness.model.send(.accountIdentifierChanged("other-account"))
        await harness.waitForGateWaiting(1)

        XCTAssertNil(harness.loadedContent)
        XCTAssertEqual(harness.model.state.phase, .loading)
        XCTAssertEqual(harness.recorder.calls.last, DrivingRouteLoadRecorder.Call(sessionID: session.id, accountIdentifier: "other-account"))
        harness.gate.release(session.id)
        _ = try await harness.waitForLoadedContent(session.id)
    }

    /// 読み込み中にアカウントが無くなったら、読み込みを取り消し、アカウントを待ちます。
    ///
    /// 責務: nil のアカウントで `waitingForAccount` になり、止めていた読み込みを再開しても結果で上書きしないことを確認します。
    func testAccountRemovalDuringLoadCancelsAndWaitsForAccount() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        harness.gate.hold(session.id)
        showWithAccount(session)
        await harness.waitForGateWaiting(1)

        harness.model.send(.accountIdentifierChanged(nil))
        await harness.waitForPhase(.waitingForAccount)
        harness.gate.release(session.id)
        let resumption = try await harness.waitForResumption(session.id)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(resumption.wasCancelled)
        XCTAssertEqual(harness.model.state.phase, .waitingForAccount)
    }

    /// 同じアカウントが届いても、取り消さず、読み直しません。
    ///
    /// 責務: 値の変わらないアカウントの通知で、読み込みが1回のまま内容が残ることを確認します。
    func testSameAccountDoesNotReload() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        showWithAccount(session)
        let content = try await harness.waitForLoadedContent(session.id)

        harness.model.send(.accountIdentifierChanged(DrivingRouteDetailModelHarness.account))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.recorder.calls.count, 1)
        XCTAssertEqual(harness.loadedContent, content)
    }

    /// 詳細を閉じたら、読み込みを取り消して何も表示しない状態へ戻ります。
    ///
    /// 責務: 表示中のセッションの `sessionHidden` で `idle` になり、止めていた読み込みが取り消され、再開しても結果で上書きしないことを確認します。
    func testSessionHiddenCancelsLoadAndReturnsToIdle() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        harness.gate.hold(session.id)
        showWithAccount(session)
        await harness.waitForGateWaiting(1)

        harness.model.send(.sessionHidden(session.id))
        await harness.waitForPhase(.idle)
        harness.gate.release(session.id)
        let resumption = try await harness.waitForResumption(session.id)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertTrue(resumption.wasCancelled)
        XCTAssertEqual(harness.model.state.phase, .idle)
    }

    /// 表示中でないセッションを閉じても、何も変えません。
    ///
    /// 責務: 別の ID の `sessionHidden` で、読み込み済みの内容がそのまま残ることを確認します。
    func testSessionHiddenForOtherSessionIsIgnored() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        showWithAccount(session)
        let content = try await harness.waitForLoadedContent(session.id)

        harness.model.send(.sessionHidden(ConnectionSessionID()))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state.sessionID, session.id)
        XCTAssertEqual(harness.loadedContent, content)
    }

    /// アカウントを渡してからセッションを表示します。
    ///
    /// 責務: 読み込みが始まる前提(アカウントあり)を揃えて表示を送ります。
    /// - Parameter session: 表示するセッション。
    private func showWithAccount(_ session: ConnectionSession) {
        harness.model.send(.accountIdentifierChanged(DrivingRouteDetailModelHarness.account))
        harness.model.send(.sessionShown(session))
    }
}
