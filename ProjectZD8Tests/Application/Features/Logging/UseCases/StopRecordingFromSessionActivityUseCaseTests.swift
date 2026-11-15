import XCTest
@testable import ProjectZD8

/// 記録中の[切断]操作が、手動切断と同じ取得停止の要求になり、記録中でなければ何も変えないことを検証します。
@MainActor
final class StopRecordingFromSessionActivityUseCaseTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?
    /// 停止要求の送出回数です。
    private var stopRequestCount = 0

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付け、回数を初期化します。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        stopRequestCount = 0
        try await super.tearDown()
    }

    /// 読込み済みの記録中に実行すると、ユーザー切断としてセッションが終わります。
    ///
    /// 責務: 停止要求が1回届き、待機状態へ戻り、終了理由が `userDisconnected` で通知されることを確認します。
    func testExecuteWhileLoadedEndsSessionAsUserDisconnected() async {
        let fixture = await startLoaded()
        let useCase = makeUseCase(fixture)

        useCase.execute()
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertEqual(stopRequestCount, 1)
        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
        XCTAssertNil(fixture.model.state.failureKey)
    }

    /// 初回周回の途中(接続直後)でも停止できます。
    ///
    /// 責務: 読込み前の記録中でも、停止要求が届きユーザー切断で終わることを確認します。
    func testExecuteWhileReadingEndsSessionAsUserDisconnected() async {
        let fixture = makeFixture()
        fixture.start()
        await fixture.telemetry.waitForSentRequests(1)
        XCTAssertEqual(fixture.model.state.phase, .reading)

        makeUseCase(fixture).execute()
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertEqual(stopRequestCount, 1)
        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
    }

    /// 通信の一時停止中でも停止できます。
    ///
    /// 責務: 一時停止中に実行しても停止要求が届き、ユーザー切断で終わることを確認します。
    func testExecuteWhilePausedEndsSessionAsUserDisconnected() async {
        let fixture = await startLoaded()
        await fixture.telemetry.release(.transportFailure)
        await fixture.waitUntil("一時停止") { fixture.model.state.phase == .paused }

        makeUseCase(fixture).execute()
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertEqual(stopRequestCount, 1)
        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
    }

    /// 記録していない時に実行しても、状態も永続化も変わりません。
    ///
    /// 責務: 未開始の状態で実行しても、停止要求を送らず、状態・終了通知・要求送信が変わらないことを確認します。
    func testExecuteWhileNotRecordingChangesNothing() async {
        let fixture = makeFixture()
        let before = fixture.model.state

        makeUseCase(fixture).execute()
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(stopRequestCount, 0)
        XCTAssertEqual(fixture.model.state, before)
        XCTAssertEqual(fixture.notifications.endReasons, [])
        XCTAssertEqual(fixture.telemetry.sentRequests, [])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [])
    }

    /// 終了後に実行しても、終了を重ねて通知しません。
    ///
    /// 責務: 手動切断で終わった後に実行しても停止要求を送らず、終了通知が1件のままであることを確認します。
    func testExecuteAfterSessionEndedDoesNotNotifyAgain() async {
        let fixture = await startLoaded()
        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }
        let ended = fixture.model.state

        makeUseCase(fixture).execute()
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(stopRequestCount, 0)
        XCTAssertEqual(fixture.model.state, ended)
        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
    }

    /// 停止処理中に重ねて実行しても、停止要求は増えません。
    ///
    /// 責務: 1回目の実行で停止処理中になった後の2回目が、停止要求を送らず終了通知も1件のままであることを確認します。
    func testExecuteWhileStoppingDoesNotRequestStopAgain() async {
        let fixture = await startLoaded()
        let useCase = makeUseCase(fixture)

        useCase.execute()
        XCTAssertEqual(fixture.model.state.phase, .stopping)
        useCase.execute()
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertEqual(stopRequestCount, 1)
        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
    }

    /// 読取失敗で終わった後に実行しても、停止要求を送りません。
    ///
    /// 責務: 失敗状態は記録中ではないため、実行しても状態と終了通知が変わらないことを確認します。
    func testExecuteAfterFailureChangesNothing() async {
        let fixture = LiveTelemetryModelFixture(catalog: [], failsCatalog: true)
        self.fixture = fixture
        fixture.start()
        await fixture.waitUntil("失敗表示") { fixture.model.state.phase == .failed }
        let failed = fixture.model.state

        makeUseCase(fixture).execute()
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(stopRequestCount, 0)
        XCTAssertEqual(fixture.model.state, failed)
        XCTAssertEqual(fixture.notifications.endReasons, [.acquisitionFailed])
    }

    /// PID 2件だけを取得対象にしたモデル部品を生成して保持します。
    ///
    /// 責務: 記録ポートなしのモデル部品を組み立て、tearDown で片付けられるよう保持します。
    /// - Returns: 未開始のモデル部品。
    private func makeFixture() -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x31, 0xA6]))
        self.fixture = fixture
        return fixture
    }

    /// 開始して初回周回を終え、読込み済みにします。
    ///
    /// 責務: 初回周回の2件へ応答を返し、読込み済みになるまで上限付きで待ちます。
    /// - Returns: 読込み済みのモデル部品。
    private func startLoaded() async -> LiveTelemetryModelFixture {
        let fixture = makeFixture()
        fixture.start()
        await fixture.telemetry.answer(2) { _ in .responded([1]) }
        await fixture.waitUntil("読み込み済み") { fixture.model.state.phase == .loaded }
        return fixture
    }

    /// モデルの状態と停止要求を結んだユースケースを生成します。
    ///
    /// 責務: 本番の配線と同じく `stopRequested` を送り、送出回数を数える停止要求先を注入します。
    /// - Parameter fixture: 対象のモデル部品。
    /// - Returns: 検証対象のユースケース。
    private func makeUseCase(_ fixture: LiveTelemetryModelFixture) -> StopRecordingFromSessionActivityUseCase {
        StopRecordingFromSessionActivityUseCase(
            telemetryState: { fixture.model.state },
            requestStop: { [weak self] in
                self?.stopRequestCount += 1
                fixture.model.send(.stopRequested)
            }
        )
    }
}
