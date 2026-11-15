import Foundation
import XCTest
@testable import ProjectZD8

/// LiveTelemetryModel が、取得の開始・段階の変化・終了を診断記録へ1回ずつ、流れた順と同じ値で渡すことを検証します。
///
/// 段階の期待値は取得ループの仕様(`LiveTelemetryAcquisitionLoopRecoveryTests` が検証する回復段階の順と上限回数)から書きます。
@MainActor
final class LiveTelemetryModelAcquisitionDiagnosticsTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 取得を始めて停止の指示で終えると、開始と停止がそれぞれ1回だけ記録されます。
    ///
    /// 責務: 開始の記録と、停止の指示による終了 → stopped を1回だけ記録することを確認します。
    func testStartAndUserStopAreRecordedOnce() async throws {
        let (fixture, diagnostics) = makeFixture()
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("読み込み済み") { fixture.model.state.phase == .loaded }
        XCTAssertEqual(diagnostics.events, [.started])

        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(diagnostics.events, [.started, .stopped])
    }

    /// 回復して取得中へ戻ると、回復中(原因・段階・試行番号つき)と取得中が流れた順に1回ずつ記録されます。
    ///
    /// 責務: リンク断から確認要求の再同期で復帰する経路の段階の記録を確認します。終了は記録されません。
    func testRecoveryAndResumePhasesAreRecordedInOrder() async {
        let (fixture, diagnostics) = makeFixture()
        fixture.linkRecovery.schedule([true])
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.telemetry.release(.transportFailure)
        await fixture.telemetry.release(.responded([2]))

        await fixture.waitUntil("取得中への復帰") { diagnostics.phases.count >= 2 }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(diagnostics.phases, [.recovering(cause: .linkLost, stage: .promptResync, attempt: 1), .acquiring])
        XCTAssertEqual(diagnostics.startCount, 1)
        XCTAssertEqual(diagnostics.terminations, [])
    }

    /// 回復を使い切って一時停止し猶予切れで終わると、全回復段階・一時停止・猶予切れが順に1回ずつ記録され、後の停止で二重に記録されません。
    ///
    /// 責務: 回復段階の全試行(原因つき)、paused(原因つき)、gracePeriodExpired(原因つき)の記録と重複のなさを確認します。
    func testExhaustedRecoveryPauseAndGraceExpiryAreRecordedOnce() async {
        let (fixture, diagnostics) = makeFixture()
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.telemetry.release(.transportFailure)
        await fixture.waitUntil("一時停止") { diagnostics.phases.last == .paused(cause: .linkLost) }

        XCTAssertEqual(diagnostics.phases, Self.exhaustedRecoveryPhases(cause: .linkLost))
        fixture.clock.advance(byNanoseconds: 180 * 1_000_000_000 + 1)
        fixture.model.send(.foregroundTransitionOccurred)
        await fixture.waitUntil("猶予切れの終了") { !diagnostics.terminations.isEmpty }
        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(diagnostics.terminations, [.gracePeriodExpired(.linkLost)])
        XCTAssertEqual(diagnostics.events.first, .started)
        XCTAssertEqual(diagnostics.events.last, .gracePeriodExpired(.linkLost))
        XCTAssertEqual(diagnostics.startCount, 1)
    }

    /// 取得中の記録の失敗で終わると、recordingFailed が1回だけ記録されます。
    ///
    /// 責務: 取得ループの出来事による記録失敗の終了を確認します。
    func testRecordingFailureDuringAcquisitionIsRecordedOnce() async {
        let recorder = LiveTelemetryRecordingPortSpy(failing: .record)
        let (fixture, diagnostics) = makeFixture(recorder: recorder)
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("失敗表示") { fixture.model.state.phase == .failed }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(diagnostics.terminations, [.recordingFailed])
        XCTAssertEqual(diagnostics.startCount, 1)
    }

    /// 停止の指示で記録の終了が失敗すると、stopped ではなく recordingFailed が1回だけ記録されます。
    ///
    /// 責務: 停止の経路で返った終了理由の記録と、二重に記録しないことを確認します。
    func testRecordingFailureOnUserStopIsRecordedOnceAsRecordingFailed() async {
        let recorder = LiveTelemetryRecordingPortSpy(failing: .finish)
        let (fixture, diagnostics) = makeFixture(recorder: recorder)
        fixture.start()
        await fixture.telemetry.waitForSentRequests(1)

        fixture.model.send(.stopRequested)
        await fixture.waitUntil("停止の完了") { fixture.model.state.phase == .failed }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(diagnostics.terminations, [.recordingFailed])
    }

    /// 取得を始める前の準備に失敗すると、開始も終了も記録されません。
    ///
    /// 責務: カタログ読込の失敗で取得ループが始まらない経路で、診断記録が空のままであることを確認します。
    func testPreparationFailureRecordsNoStart() async {
        let (fixture, diagnostics) = makeFixture(catalog: [], failsCatalog: true)
        fixture.start()
        await fixture.waitUntil("失敗表示") { fixture.model.state.phase == .failed }
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(diagnostics.events, [])
    }

    /// 診断記録を注入しなくても、取得と停止は従来どおり動きます。
    ///
    /// 責務: 診断記録なしの構成で、読み込み済みから停止して待機状態へ戻り、ユーザー切断が通知されることを確認します。
    func testWorksWithoutDiagnostics() async {
        let fixture = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x0C]))
        self.fixture = fixture
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.waitUntil("読み込み済み") { fixture.model.state.phase == .loaded }

        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertNil(fixture.acquisitionDiagnostics)
        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
    }

    /// 回復段階をすべて上限回数まで試して一時停止するときの、段階の列です。
    ///
    /// 責務: `AcquisitionStallPolicy` の段階別上限と、軽い処置から順に進む回復段階の仕様から期待値を作ります。
    /// - Parameter cause: 途切れの原因。
    /// - Returns: 回復中の全試行と一時停止の段階の列。
    private static func exhaustedRecoveryPhases(cause: LiveTelemetryInterruptionCause) -> [LiveTelemetryAcquisitionPhase] {
        let limits: [(AcquisitionRecoveryStage, Int)] = [
            (.promptResync, AcquisitionStallPolicy.promptResyncAttemptLimit),
            (.reinitializeFromReset, AcquisitionStallPolicy.reinitializeFromResetAttemptLimit),
            (.reconnectLink, AcquisitionStallPolicy.reconnectLinkAttemptLimit)
        ]
        let recovering = limits.flatMap { stage, limit in
            (1...limit).map { LiveTelemetryAcquisitionPhase.recovering(cause: cause, stage: stage, attempt: $0) }
        }
        return recovering + [.paused(cause: cause)]
    }

    /// 診断記録の spy を注入したモデル部品を作り、後片付けの対象にします。
    ///
    /// 責務: 指定のカタログ・失敗指定・記録ポートで、spy を注入したモデル部品と spy を返します。
    /// - Parameters:
    ///   - catalog: PIDカタログの定義。既定は PID 0x0C だけ。
    ///   - failsCatalog: カタログ読込を失敗させる場合は `true`。
    ///   - recorder: 記録ポートのスパイ。
    /// - Returns: モデル部品と診断記録の spy。
    private func makeFixture(
        catalog: [OBDPIDDefinition] = LiveTelemetryTestDefinitions.standard([0x0C]),
        failsCatalog: Bool = false,
        recorder: LiveTelemetryRecordingPortSpy? = nil
    ) -> (LiveTelemetryModelFixture, LiveTelemetryAcquisitionDiagnosticsSpy) {
        let diagnostics = LiveTelemetryAcquisitionDiagnosticsSpy()
        let fixture = LiveTelemetryModelFixture(
            catalog: catalog,
            failsCatalog: failsCatalog,
            recorder: recorder,
            acquisitionDiagnostics: diagnostics
        )
        self.fixture = fixture
        return (fixture, diagnostics)
    }
}
