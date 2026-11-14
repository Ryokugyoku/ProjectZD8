import Foundation
import XCTest
@testable import ProjectZD8

/// LiveTelemetryModel の開始・失敗表示・終了理由ごとの状態・累積距離通知を検証します。
@MainActor
final class LiveTelemetryModelTests: XCTestCase {
    /// 各テストのモデル部品です。
    private var fixture: LiveTelemetryModelFixture?

    /// 動いている取得を止めます。
    ///
    /// 責務: テストごとに応答待ちの要求と取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 初回周回の後も要求を送り続け、停止で待機状態へ戻ります。
    ///
    /// 責務: 開始が単発読取ではなく継続取得になり、停止がendSession後に待機状態になることを確認します。
    func testStartContinuesPollingAfterInitialRound() async {
        let fixture = make(catalog: LiveTelemetryTestDefinitions.standard([0x0C, 0x0D]))
        fixture.start()
        XCTAssertEqual(fixture.model.state.phase, .reading)
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true])

        await fixture.telemetry.answer(4) { _ in .responded([1]) }
        await fixture.telemetry.waitForSentRequests(5)
        XCTAssertEqual(fixture.model.state.phase, .loaded)
        fixture.model.send(.stopRequested)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
        XCTAssertGreaterThanOrEqual(fixture.telemetry.endSessionCount, 1)
    }

    /// PIDカタログを読めなければ専用の失敗表示になり、要求を送りません。
    ///
    /// 責務: カタログ利用不能をスリープ抑止解除済みの専用失敗表示と取得失敗の通知へ変換することを確認します。
    func testCatalogFailureMapsToDedicatedMessage() async {
        let fixture = make(catalog: [], failsCatalog: true)
        fixture.start()

        await fixture.waitUntil("失敗表示") { fixture.model.state.phase == .failed }

        XCTAssertEqual(fixture.model.state.failureKey, "telemetry.error.pid_catalog_unavailable")
        XCTAssertEqual(fixture.notifications.endReasons, [.acquisitionFailed])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true, false])
        XCTAssertEqual(fixture.telemetry.sentRequests, [])
    }

    /// リンク断の猶予切れによる終了は、未接続状態・接続断の表示キーと、最後の受信時刻付きの接続断の通知になります。
    ///
    /// 責務: 一時停止から猶予を過ぎた起床で終了し、`sessionDidEnd` が最後に正常応答を受けた実時刻で呼ばれることを確認します。
    func testGraceExpiryAfterLinkLossMapsToDisconnectedState() async {
        let fixture = make(catalog: LiveTelemetryTestDefinitions.standard([0x0C]))
        fixture.start()
        await fixture.telemetry.release(.responded([1]))
        await fixture.telemetry.release(.transportFailure)
        await fixture.waitUntil("一時停止") { fixture.model.state.pauseStatus?.isRecovering == false }
        fixture.dates.set(Date(timeIntervalSince1970: 9_999))
        fixture.clock.advance(byNanoseconds: 180 * 1_000_000_000 + 1)

        fixture.model.send(.foregroundTransitionOccurred)
        await fixture.waitUntil("接続断の終了") { fixture.model.state.failureKey != nil }

        XCTAssertEqual(fixture.model.state.phase, .idle)
        XCTAssertNil(fixture.model.state.pauseStatus)
        XCTAssertEqual(fixture.model.state.failureKey, "telemetry.disconnected.connection_lost")
        XCTAssertEqual(fixture.notifications.endReasons, [.connectionLost])
        XCTAssertEqual(fixture.notifications.endedAts, [Date(timeIntervalSince1970: 1_000)])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true, false])
    }

    /// 記録の失敗による終了は読取失敗の表示になります。
    ///
    /// 責務: `recordingFailed` を失敗状態・読取失敗表示・取得失敗通知へ変換することを確認します。
    func testRecordingFailureMapsToReadFailed() async {
        let fixture = make(catalog: LiveTelemetryTestDefinitions.standard([0x0C]), recorder: LiveTelemetryRecordingPortSpy(failing: .record))
        fixture.start()
        await fixture.telemetry.release(.responded([1]))

        await fixture.waitUntil("失敗表示") { fixture.model.state.phase == .failed }

        XCTAssertEqual(fixture.model.state.failureKey, "telemetry.error.read_failed")
        XCTAssertEqual(fixture.notifications.endReasons, [.acquisitionFailed])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true, false])
    }

    /// 記録の開始に失敗すると要求を1件も送らずに読取失敗の表示になります。
    ///
    /// 責務: manifest保存相当の開始失敗が物理要求0件の取得失敗になることを確認します。
    func testRecordingStartFailurePreventsEveryRequest() async {
        let fixture = make(catalog: LiveTelemetryTestDefinitions.standard([0x0C]), recorder: LiveTelemetryRecordingPortSpy(failing: .start))
        fixture.start()

        await fixture.waitUntil("失敗表示") { fixture.model.state.phase == .failed }

        XCTAssertEqual(fixture.telemetry.sentRequests, [])
        XCTAssertEqual(fixture.model.state.failureKey, "telemetry.error.read_failed")
        XCTAssertEqual(fixture.notifications.endReasons, [.acquisitionFailed])
    }

    /// 停止時に記録の終了が失敗すると、待機状態ではなく読取失敗の表示になります。
    ///
    /// 責務: 停止時の保存失敗を成功扱いせず、取得失敗として通知することを確認します。
    func testStopWithRecordingFailureMapsToReadFailed() async {
        let fixture = make(catalog: LiveTelemetryTestDefinitions.standard([0x0C]), recorder: LiveTelemetryRecordingPortSpy(failing: .finish))
        fixture.start()
        await fixture.telemetry.waitForSentRequests(1)

        fixture.model.send(.stopRequested)
        await fixture.waitUntil("停止の完了") { fixture.model.state.phase != .stopping }

        XCTAssertEqual(fixture.model.state.phase, .failed)
        XCTAssertEqual(fixture.model.state.failureKey, "telemetry.error.read_failed")
        XCTAssertEqual(fixture.notifications.endReasons, [.acquisitionFailed])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true, false])
    }

    /// バックグラウンド移行で現在の世代の保存待ちをflushさせます。
    ///
    /// 責務: バックグラウンド移行の操作が記録ポートへ契機付きのflushとして届くことを確認します。
    func testBackgroundTransitionFlushesCurrentGeneration() async {
        let recorder = LiveTelemetryRecordingPortSpy()
        let fixture = make(catalog: LiveTelemetryTestDefinitions.standard([0x0C]), recorder: recorder)
        fixture.start()
        await fixture.telemetry.waitForSentRequests(1)

        fixture.model.send(.backgroundTransitionOccurred)

        let arrived = await LiveTelemetryBoundedWaiter.waitUntil("flushの到着") {
            let calls = await recorder.calls
            return calls.contains(.flush(.backgroundTransition, generation: 1))
        }

        XCTAssertTrue(arrived)
    }

    /// A6の観測を累積走行距離として通知します。
    ///
    /// 責務: 数値化済み Service 01 PID A6 が走行距離の通知になることを確認します。
    func testOdometerSampleNotifiesDistance() async {
        let fixture = make(catalog: LiveTelemetryTestDefinitions.standard([0xA6]))
        fixture.start()
        await fixture.telemetry.release(.responded([123]))

        await fixture.waitUntil("距離通知") { !fixture.notifications.distances.isEmpty }

        XCTAssertEqual(fixture.notifications.distances.first, .init(source: .odometer, kilometers: 123))
    }

    /// A6が無ければPID 31の観測を代替の累積距離として通知します。
    ///
    /// 責務: 数値化済み Service 01 PID 31 が取得元付きの距離通知になることを確認します。
    func testDistanceSinceCodesClearedNotifiesFallback() async {
        let fixture = make(catalog: LiveTelemetryTestDefinitions.standard([0x31]))
        fixture.start()
        await fixture.telemetry.release(.responded([200]))

        await fixture.waitUntil("距離通知") { !fixture.notifications.distances.isEmpty }

        XCTAssertEqual(fixture.notifications.distances.first, .init(source: .distanceSinceCodesCleared, kilometers: 200))
    }

    /// ZD8型式では専用PIDも同じ取得で表示し、専用走行距離をA6より優先して通知します。
    ///
    /// 責務: 車種専用PIDの観測が表示と型式付きの距離通知へ反映されることを確認します。
    func testZD8VehicleSpecificOdometerIsDisplayedAndNotified() async {
        let catalog = LiveTelemetryTestDefinitions.standard([0x0C, 0xA6]) + ZD8OBDPIDSeed.definitions
        let fixture = make(catalog: catalog)
        fixture.start(vehicleModelCode: ZD8VehicleModelPolicy.modelCode)
        await fixture.telemetry.answer(catalog.count) { request in
            request.service == 0x21 ? .responded([0x00, 0x01, 0xE2, 0x40]) : .responded([10])
        }

        await fixture.waitUntil("読み込み済み") { fixture.model.state.phase == .loaded }

        XCTAssertEqual(fixture.model.state.vehicleModelCode, ZD8VehicleModelPolicy.modelCode)
        XCTAssertEqual(Set(fixture.model.state.samples.map(\.request)), Set(catalog.map(LiveTelemetryTestDefinitions.request)))
        XCTAssertEqual(
            fixture.notifications.distances.first,
            .init(source: .vehicleSpecificOdometer, kilometers: 12_345.6, vehicleModelCode: ZD8VehicleModelPolicy.modelCode)
        )
    }

    /// モデル部品を生成して後片付けの対象にします。
    ///
    /// 責務: カタログ・失敗指定・記録ポートを固定したモデル部品を返します。
    /// - Parameters:
    ///   - catalog: PIDカタログの定義。
    ///   - failsCatalog: カタログ読込を失敗させる場合は `true`。
    ///   - recorder: 記録ポートのスパイ。
    /// - Returns: モデル部品。
    private func make(
        catalog: [OBDPIDDefinition],
        failsCatalog: Bool = false,
        recorder: LiveTelemetryRecordingPortSpy? = nil
    ) -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: catalog, failsCatalog: failsCatalog, recorder: recorder)
        self.fixture = fixture
        return fixture
    }
}
