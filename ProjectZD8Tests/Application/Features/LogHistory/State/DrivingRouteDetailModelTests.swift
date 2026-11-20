import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの詳細のモデルが、読み込みの結果に応じて状態を変えることを検証します。
///
/// 読み込みは実物の `LoadConnectionSessionLocationTrackUseCase` をフェイクのリポジトリで動かします。
/// 非同期の結果は期限(2秒)つきで待ちます。
@MainActor
final class DrivingRouteDetailModelTests: XCTestCase {
    /// モデルと部品の組です。
    private var harness = DrivingRouteDetailModelHarness()
    /// 位置情報が拒否されていた区間の注記のキーです。
    private let partialDeniedKey = "history.route.notice.partial.authorization_denied"

    /// 責務: 止めた読み込みを必ず再開し、終わらないテストを残しません。
    override func tearDown() async throws {
        harness.gate.releaseAll()
        try await super.tearDown()
    }

    /// 作った直後は何も表示していません。
    ///
    /// 責務: 初期状態がセッション無しの `idle` であることを確認します。
    func testInitialStateIsIdle() {
        XCTAssertEqual(harness.model.state, DrivingRouteDetailState(sessionID: nil, phase: .idle))
    }

    /// アカウントが無い間は、アカウントを待ち、読み込みません。
    ///
    /// 責務: 表示しても `waitingForAccount` になり、読み込みが一度も呼ばれないことを確認します。
    func testWithoutAccountWaitsAndDoesNotLoad() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))

        harness.model.send(.sessionShown(session))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state.phase, .waitingForAccount)
        XCTAssertEqual(harness.recorder.calls, [])
    }

    /// 空文字のアカウントはサインインなしとみなし、読み込みません。
    ///
    /// 責務: 空文字のアカウントで表示しても `waitingForAccount` になり、読み込みが呼ばれないことを確認します。
    func testEmptyAccountIsTreatedAsNoAccount() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))

        harness.model.send(.accountIdentifierChanged(""))
        harness.model.send(.sessionShown(session))
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state, DrivingRouteDetailState(sessionID: session.id, phase: .waitingForAccount))
        XCTAssertEqual(harness.recorder.calls, [])
    }

    /// アカウントが来たら、待っていたセッションを読みます。
    ///
    /// 責務: 表示の後に届いたアカウントで読み込みが始まり、地図の内容が出ることを確認します。
    func testAccountArrivalLoadsPendingSession() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        harness.model.send(.sessionShown(session))

        harness.model.send(.accountIdentifierChanged(DrivingRouteDetailModelHarness.account))

        _ = try await harness.waitForLoadedContent(session.id)
        XCTAssertEqual(harness.recorder.calls.map(\.sessionID), [session.id])
    }

    /// 読み込みは表示したセッションの ID と現在のアカウントで呼びます。
    ///
    /// 責務: 読み込みの引数がセッション ID とアカウント識別子であることを確認します。
    func testLoadUsesSessionIDAndAccount() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))

        showWithAccount(session)

        _ = try await harness.waitForLoadedContent(session.id)
        XCTAssertEqual(
            harness.recorder.calls,
            [DrivingRouteLoadRecorder.Call(sessionID: session.id, accountIdentifier: DrivingRouteDetailModelHarness.account)]
        )
    }

    /// 読み込みの途中は、そのセッションで読み込み中です。
    ///
    /// 責務: 読み込みを止めている間、状態がセッション ID 付きの `loading` であることを確認します。
    func testPhaseIsLoadingWhileLoadIsPending() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        harness.gate.hold(session.id)

        showWithAccount(session)
        await harness.waitForGateWaiting(1)

        XCTAssertEqual(harness.model.state, DrivingRouteDetailState(sessionID: session.id, phase: .loading))
    }

    /// 点のある軌跡を読むと、線・印・要約・注記のある地図の内容になります。
    ///
    /// 責務: 途中から記録された終了済みのセッションで、1本の線・出発と到着の印・部分の注記・要約が出ることを確認します。
    func testLoadedContentHasGeometrySummaryAndNotices() async throws {
        let session = DrivingRouteTestValues.session(hasEnded: true)
        let track = try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 5)
        harness.addLocalTrack(track)

        showWithAccount(session)
        let content = try await harness.waitForLoadedContent(session.id)

        XCTAssertEqual(content.noticeKeys, [partialDeniedKey])
        XCTAssertEqual(content.geometry.polylines.count, 1)
        XCTAssertEqual(Set(content.geometry.markers.map(\.endpoint)), [.start, .end])
        XCTAssertEqual(content.summary.lengthText.filter(\.isNumber), "44", content.summary.lengthText)
        XCTAssertNotEqual(content.summary.coverageText, "—")
    }

    /// 事象だけの軌跡は、理由を出す表示になります。
    ///
    /// 責務: 拒否の事象だけの軌跡で、拒否の理由のキーと空の注記の `unavailable` になることを確認します。
    func testEventsOnlyTrackIsUnavailableWithReason() async {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(DrivingRouteTestValues.track(sessionID: session.id, eventKinds: [.authorizationDenied]))

        showWithAccount(session)

        await LocationRecordingBoundedWaiter.waitUntil("unavailable") { self.unavailableContent()?.0 != nil }
        XCTAssertEqual(unavailableContent()?.0.messageKey, "history.route.absence.authorization_denied")
        XCTAssertEqual(unavailableContent()?.1, [])
    }

    /// iCloud にも無いなら、理由 notInCloud の表示になります。
    ///
    /// 責務: この端末にも iCloud にも軌跡が無いセッションで、`absence.not_in_cloud` の `unavailable` になることを確認します。
    func testNotInCloudIsUnavailable() async {
        let session = DrivingRouteTestValues.session()
        harness.registerSessionWithoutLocalTrack(session.id)

        showWithAccount(session)

        await LocationRecordingBoundedWaiter.waitUntil("unavailable") { self.unavailableContent()?.0 != nil }
        XCTAssertEqual(unavailableContent()?.0.messageKey, "history.route.absence.not_in_cloud")
        XCTAssertEqual(unavailableContent()?.1, [])
    }

    /// 新しい形式の軌跡は再試行できない失敗になり、再試行を無視します。
    ///
    /// 責務: `unsupportedPayloadFormat` で更新のキーの `failed(isRetryable: false)` になり、再試行で読み直さないことを確認します。
    func testUpdateRequiredFailsWithoutRetry() async {
        let session = DrivingRouteTestValues.session()
        harness.registerSessionWithoutLocalTrack(session.id)
        harness.cloudRepository.setFailure(ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat(version: 9), for: .download)
        let expected = DrivingRouteDetailPhase.failed(
            DrivingRouteFailure(messageKey: "history.route.failure.update_required", isRetryable: false)
        )

        showWithAccount(session)
        await harness.waitForPhase(expected)
        harness.model.send(.retryRequested)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state.phase, expected)
        XCTAssertEqual(harness.recorder.calls.count, 1)
    }

    /// 一般の失敗は再試行できる失敗になり、再試行で読み直して成功します。
    ///
    /// 責務: 通信の失敗で `failed(isRetryable: true)` になり、失敗を解いてからの再試行で地図の内容が出ることを確認します。
    func testGeneralFailureRetriesAndSucceeds() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addCloudOnlyTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        harness.cloudRepository.setFailure(URLError(.timedOut), for: .download)

        showWithAccount(session)
        await harness.waitForPhase(.failed(DrivingRouteFailure(messageKey: "history.route.failure.load", isRetryable: true)))
        harness.cloudRepository.setFailure(nil, for: .download)
        harness.model.send(.retryRequested)

        let content = try await harness.waitForLoadedContent(session.id)
        XCTAssertEqual(content.noticeKeys, [partialDeniedKey])
        XCTAssertEqual(harness.recorder.calls.count, 2)
    }

    /// 失敗していない時の再試行は無視します。
    ///
    /// 責務: 読み込み済みの時に再試行を送っても、読み直さないことを確認します。
    func testRetryIsIgnoredWhenLoaded() async throws {
        let session = DrivingRouteTestValues.session()
        harness.addLocalTrack(try harness.partiallyRecordedTrack(sessionID: session.id, sampleCount: 3))
        showWithAccount(session)
        let content = try await harness.waitForLoadedContent(session.id)

        harness.model.send(.retryRequested)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.recorder.calls.count, 1)
        XCTAssertEqual(harness.loadedContent, content)
    }

    /// 取消のエラーは失敗の表示にしません。
    ///
    /// 責務: 読み込みが `CancellationError` を投げた時、状態が `loading` のまま変わらないことを確認します。
    func testCancellationErrorDoesNotChangeState() async throws {
        let session = DrivingRouteTestValues.session()
        harness.registerSessionWithoutLocalTrack(session.id)
        harness.cloudRepository.setFailure(CancellationError(), for: .download)

        showWithAccount(session)
        _ = try await harness.waitForResumption(session.id)
        await LocationRecordingBoundedWaiter.settle()

        XCTAssertEqual(harness.model.state, DrivingRouteDetailState(sessionID: session.id, phase: .loading))
    }

    /// アカウントを渡してからセッションを表示します。
    ///
    /// 責務: 読み込みが始まる前提(アカウントあり)を揃えて表示を送ります。
    /// - Parameter session: 表示するセッション。
    private func showWithAccount(_ session: ConnectionSession) {
        harness.model.send(.accountIdentifierChanged(DrivingRouteDetailModelHarness.account))
        harness.model.send(.sessionShown(session))
    }

    /// 現在の状態が `unavailable` なら、その内容と注記のキーです。
    ///
    /// 責務: `unavailable` の関連値を取り出します。
    /// - Returns: 表示できない時の内容と注記のキー。それ以外の状態なら nil。
    private func unavailableContent() -> (DrivingRouteUnavailableContent, [String])? {
        if case let .unavailable(content, noticeKeys) = harness.model.state.phase { return (content, noticeKeys) }
        return nil
    }
}
