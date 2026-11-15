import XCTest
@testable import ProjectZD8

/// 記録中の[切断]操作が、停止を送ったときだけ「accepted」を、何もしなかったときだけ「declined」を1回記録することを検証します。
@MainActor
final class StopRecordingFromSessionActivityUseCaseDiagnosticsTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?
    /// 停止要求の送出回数です。
    private var stopRequestCount = 0
    /// 状態遷移の診断記録の spy です。
    private var diagnostics = RecordingSessionActivityLifecycleDiagnosticsSpy()

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付け、回数と spy を初期化します。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        stopRequestCount = 0
        diagnostics = RecordingSessionActivityLifecycleDiagnosticsSpy()
        try await super.tearDown()
    }

    /// 記録中で停止処理中でないときは、停止が送られ、accepted が1回だけ記録されます。
    ///
    /// 責務: 受け付けた停止要求の記録を確認します。
    func testRecordingRequestIsAcceptedOnce() async {
        let fixture = await startLoaded()

        let requested = makeUseCase(fixture).execute()

        XCTAssertTrue(requested)
        XCTAssertEqual(stopRequestCount, 1)
        XCTAssertEqual(diagnostics.events, [.stopRequestAccepted])
    }

    /// 記録中でないときは、停止は送られず、declined が1回だけ記録されます。
    ///
    /// 責務: 未開始の状態での断った停止要求の記録を確認します。
    func testNotRecordingRequestIsDeclinedOnce() {
        let fixture = makeFixture()

        let requested = makeUseCase(fixture).execute()

        XCTAssertFalse(requested)
        XCTAssertEqual(stopRequestCount, 0)
        XCTAssertEqual(diagnostics.events, [.stopRequestDeclined])
    }

    /// 停止処理中に重ねて要求すると、停止は送られず、その要求について declined が1回だけ記録されます。
    ///
    /// 責務: 1回目の受付の後の2回目が断られ、accepted が増えないことを確認します。
    func testRequestWhileStoppingIsDeclinedOnce() async {
        let fixture = await startLoaded()
        let useCase = makeUseCase(fixture)
        useCase.execute()
        XCTAssertEqual(fixture.model.state.phase, .stopping)

        let requested = useCase.execute()

        XCTAssertFalse(requested)
        XCTAssertEqual(stopRequestCount, 1)
        XCTAssertEqual(diagnostics.events, [.stopRequestAccepted, .stopRequestDeclined])
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }
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

    /// モデルの状態・停止要求・診断記録の spy を結んだユースケースを生成します。
    ///
    /// 責務: 本番の配線と同じく `stopRequested` を送り、送出回数を数える停止要求先と spy を注入します。
    /// - Parameter fixture: 対象のモデル部品。
    /// - Returns: 検証対象のユースケース。
    private func makeUseCase(_ fixture: LiveTelemetryModelFixture) -> StopRecordingFromSessionActivityUseCase {
        StopRecordingFromSessionActivityUseCase(
            telemetryState: { fixture.model.state },
            requestStop: { [weak self] in
                self?.stopRequestCount += 1
                fixture.model.send(.stopRequested)
            },
            lifecycleDiagnostics: diagnostics
        )
    }
}
