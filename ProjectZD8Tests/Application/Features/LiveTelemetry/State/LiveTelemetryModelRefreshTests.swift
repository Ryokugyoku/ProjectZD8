import Foundation
import XCTest
@testable import ProjectZD8

/// LiveTelemetryModel が観測の表示更新を間引き、フェーズ変化では間引かないことを検証します。
@MainActor
final class LiveTelemetryModelRefreshTests: XCTestCase {
    /// PID 0x31(故障コード消去後の走行距離)の要求です。
    private let distanceSinceCleared = LiveTelemetryTestDefinitions.request(0x31)
    /// PID 0xA6(累積走行距離)の要求です。
    private let odometer = LiveTelemetryTestDefinitions.request(0xA6)
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

    /// 最小間隔内に複数の観測が届いても表示更新は1回で、間引いた観測は次の更新で反映されます。
    ///
    /// 責務: 累積距離通知の回数を表示更新の回数として数え、間隔内の2件が表示されず、間隔経過後の更新でまとめて反映されることを確認します。
    func testSamplesWithinMinimumIntervalAreRefreshedOnceAndHeldSamplesAppearLater() async {
        let fixture = await startLoaded()
        await fixture.telemetry.release(.responded([3]))
        await fixture.telemetry.release(.responded([2]))
        await fixture.telemetry.waitForSentRequests(5)
        await LiveTelemetryBoundedWaiter.settle()
        XCTAssertEqual(fixture.displayedValues, [distanceSinceCleared: 1, odometer: 1])
        XCTAssertEqual(fixture.notifications.distances.count, 1)

        fixture.clock.advance(byNanoseconds: LiveTelemetryDisplayRefreshThrottle.minimumIntervalNanoseconds)
        await fixture.telemetry.release(.responded([5]))
        await fixture.waitUntil("間隔経過後の表示更新") { fixture.displayedValues[self.distanceSinceCleared] == 5 }
        XCTAssertEqual(fixture.displayedValues[odometer], 2)
        await fixture.telemetry.release(.responded([6]))
        await fixture.telemetry.waitForSentRequests(7)
        await LiveTelemetryBoundedWaiter.settle()

        XCTAssertEqual(fixture.displayedValues, [distanceSinceCleared: 5, odometer: 2])
        XCTAssertEqual(fixture.notifications.distances, [
            ConnectionSessionDistanceObservation(source: .odometer, kilometers: 1),
            ConnectionSessionDistanceObservation(source: .odometer, kilometers: 2)
        ])
    }

    /// 読み込み完了は間隔を待たずに、初回周回の観測をすべて表示します。
    ///
    /// 責務: 取得対象の確定で、時計を進めなくても読み込み済みと全観測が反映されることを確認します。
    func testTargetsConfirmationIsNotThrottled() async {
        let fixture = await startLoaded()

        XCTAssertEqual(fixture.model.state.phase, .loaded)
        XCTAssertEqual(fixture.model.state.supportedPIDCount, 2)
        XCTAssertEqual(fixture.model.state.samples.map(\.request), [distanceSinceCleared, odometer])
    }

    /// 無応答による終了は間引かれず、保留中の観測を反映してから未接続状態になります。
    ///
    /// 責務: 終了時に間隔内の観測が表示され、無応答の表示キー・終了通知・スリープ抑止解除になることを確認します。
    func testNoVehicleResponseAppliesHeldSamplesAndDisconnects() async {
        let fixture = await startLoaded()
        await fixture.telemetry.release(.responded([7]))
        await fixture.telemetry.release(.responded([8]))
        await fixture.telemetry.answer(2) { _ in .timedOut }

        await fixture.waitUntil("無応答の終了") { fixture.model.state.failureKey != nil }

        XCTAssertEqual(fixture.displayedValues, [distanceSinceCleared: 7, odometer: 8])
        XCTAssertEqual(fixture.model.state.phase, .idle)
        XCTAssertEqual(fixture.model.state.failureKey, "telemetry.disconnected.no_response")
        XCTAssertEqual(fixture.notifications.endReasons, [.vehicleNoResponse])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true, false])
        XCTAssertEqual(fixture.telemetry.endSessionCount, 1)
    }

    /// 停止は間引かれず、保留中の観測を反映してから待機状態になります。
    ///
    /// 責務: 停止時に間隔内の観測が表示され、ユーザー切断の通知とスリープ抑止解除になることを確認します。
    func testStopAppliesHeldSamplesAndBecomesIdle() async {
        let fixture = await startLoaded()
        await fixture.telemetry.release(.responded([9]))
        await fixture.telemetry.waitForSentRequests(4)
        await LiveTelemetryBoundedWaiter.settle()

        fixture.model.send(.stopRequested)
        XCTAssertEqual(fixture.model.state.phase, .stopping)
        await fixture.waitUntil("待機状態") { fixture.model.state.phase == .idle }

        XCTAssertEqual(fixture.displayedValues[distanceSinceCleared], 9)
        XCTAssertNil(fixture.model.state.failureKey)
        XCTAssertEqual(fixture.notifications.endReasons, [.userDisconnected])
        XCTAssertEqual(fixture.sleepInhibitor.connectionStates, [true, false])
        XCTAssertGreaterThanOrEqual(fixture.telemetry.endSessionCount, 1)
    }

    /// 通常PID2件だけを取得対象にして開始し、初回周回の応答で読み込み済みにします。
    ///
    /// 責務: 毎周回2件が要求される構成で初回周回へ値1を返し、表示と累積距離通知1件を待ちます。
    /// - Returns: 読み込み済みのモデル部品。
    private func startLoaded() async -> LiveTelemetryModelFixture {
        let fixture = LiveTelemetryModelFixture(catalog: LiveTelemetryTestDefinitions.standard([0x31, 0xA6]))
        self.fixture = fixture
        fixture.start()
        await fixture.telemetry.answer(2) { _ in .responded([1]) }
        await fixture.waitUntil("読み込み済み") {
            fixture.model.state.phase == .loaded && fixture.notifications.distances.count == 1
        }
        return fixture
    }
}
