import XCTest
@testable import ProjectZD8

/// 表示状態からパネルのバナー・値の表示・再試行・応答 PID 数・空判定を決める規則を検証します。
@MainActor
final class LiveTelemetryPanelContentTests: XCTestCase {
    private typealias Fixture = LiveTelemetryPanelTestFixture

    private let allPhases: [LiveTelemetryState.Phase] = [.idle, .reading, .loaded, .paused, .stopping, .failed]
    private let connectedPhases: Set<LiveTelemetryState.Phase> = [.reading, .loaded, .paused, .stopping]
    private let samples = [Fixture.sample(pid: 0x0C), Fixture.sample(pid: 0x05)]

    /// 値は接続中の4フェーズでサンプルがある時だけ出し、待機・失敗では古い値を出しません。
    ///
    /// 責務: 6フェーズについて非空サンプルでの `showsSamples` を確かめます。
    func testShowsSamplesOnlyWhileConnected() {
        for phase in allPhases {
            let content = LiveTelemetryPanelContent(state: Fixture.state(phase: phase, samples: samples))

            XCTAssertEqual(content.showsSamples, connectedPhases.contains(phase), "\(phase)")
        }
    }

    /// 接続中でもサンプルが空なら値を出しません。
    ///
    /// 責務: 接続中の4フェーズで空サンプルの `showsSamples` を確かめます。
    func testHidesSamplesWhenEmpty() {
        for phase in connectedPhases {
            XCTAssertFalse(LiveTelemetryPanelContent(state: Fixture.state(phase: phase)).showsSamples, "\(phase)")
        }
    }

    /// 失敗で接続先と車両の両方がある時だけ再試行を出します。
    ///
    /// 責務: failed で両方ありの `showsRetry` を確かめます。
    func testShowsRetryWhenFailedWithEndpointAndVehicle() {
        let state = Fixture.state(phase: .failed, endpoint: Fixture.endpoint, vehicle: Fixture.registeredVehicle)

        XCTAssertTrue(LiveTelemetryPanelContent(state: state).showsRetry)
    }

    /// 未登録の車両でも、車両の文脈があれば再試行できます。
    ///
    /// 責務: vehicle が `.unregistered` の時も非 nil として扱うことを確かめます。
    func testShowsRetryWithUnregisteredVehicle() {
        let state = Fixture.state(phase: .failed, endpoint: Fixture.endpoint, vehicle: .unregistered)

        XCTAssertTrue(LiveTelemetryPanelContent(state: state).showsRetry)
    }

    /// 失敗でも接続先か車両の片方が欠けていれば再試行を出しません。
    ///
    /// 責務: endpoint 欠け・vehicle 欠け・両方欠けの `showsRetry` を確かめます。
    func testHidesRetryWhenEndpointOrVehicleMissing() {
        let states = [
            Fixture.state(phase: .failed, vehicle: Fixture.registeredVehicle),
            Fixture.state(phase: .failed, endpoint: Fixture.endpoint),
            Fixture.state(phase: .failed)
        ]
        for state in states {
            XCTAssertFalse(LiveTelemetryPanelContent(state: state).showsRetry, "\(state)")
        }
    }

    /// 失敗以外のフェーズでは、接続先と車両があっても再試行を出しません。
    ///
    /// 責務: failed 以外の5フェーズで `showsRetry` が偽であることを確かめます。
    func testHidesRetryOutsideFailed() {
        for phase in allPhases where phase != .failed {
            let state = Fixture.state(phase: phase, endpoint: Fixture.endpoint, vehicle: Fixture.registeredVehicle)

            XCTAssertFalse(LiveTelemetryPanelContent(state: state).showsRetry, "\(phase)")
        }
    }

    /// 応答 PID 数は接続中で1以上の時だけ値を持ちます。
    ///
    /// 責務: 6フェーズについて1件の時の `respondingPIDCount` を確かめます。
    func testRespondingPIDCountOnlyWhileConnected() {
        for phase in allPhases {
            let content = LiveTelemetryPanelContent(state: Fixture.state(phase: phase, supportedPIDCount: 1))

            XCTAssertEqual(content.respondingPIDCount, connectedPhases.contains(phase) ? 1 : nil, "\(phase)")
        }
    }

    /// 接続中でも応答 PID 数が0なら値を持ちません。
    ///
    /// 責務: 0件の境界を確かめます。
    func testRespondingPIDCountIsNilWhenZero() {
        XCTAssertNil(LiveTelemetryPanelContent(state: Fixture.state(phase: .loaded, supportedPIDCount: 0)).respondingPIDCount)
        XCTAssertEqual(LiveTelemetryPanelContent(state: Fixture.state(phase: .loaded, supportedPIDCount: 42)).respondingPIDCount, 42)
    }

    /// バナーは表示状態から作った状態バナーで、無い時は nil です。
    ///
    /// 責務: `banner` の有無と中身を確かめます。
    func testBannerFollowsState() {
        let reading = LiveTelemetryPanelContent(state: Fixture.state(phase: .reading))

        XCTAssertEqual(reading.banner?.key, "telemetry.status.reading")
        XCTAssertNil(LiveTelemetryPanelContent(state: Fixture.state(phase: .idle)).banner)
    }

    /// 分類はサンプルから作った分類で、主要2値などをそのまま持ちます。
    ///
    /// 責務: `groups` が表示状態のサンプルから作られることを確かめます。
    func testGroupsAreBuiltFromSamples() {
        let content = LiveTelemetryPanelContent(state: Fixture.state(phase: .loaded, samples: samples))

        XCTAssertEqual(content.groups, LiveTelemetrySampleGroups(samples: samples))
        XCTAssertEqual(content.groups.primarySamples, samples)
    }

    /// バナー・値・再試行のどれも無い時だけ空です。
    ///
    /// 責務: 待機中で何も無い時と、古い値だけが残る時に空となることを確かめます。
    func testIsEmptyWhenNothingToShow() {
        XCTAssertTrue(LiveTelemetryPanelContent(state: Fixture.state(phase: .idle)).isEmpty)
        XCTAssertTrue(LiveTelemetryPanelContent(state: Fixture.state(phase: .idle, samples: samples)).isEmpty)
        XCTAssertTrue(LiveTelemetryPanelContent(state: Fixture.state(phase: .paused)).isEmpty)
    }

    /// バナー・値・再試行のどれか1つでもあれば空ではありません。
    ///
    /// 責務: バナーだけ・値だけ・再試行ありの各組み合わせで空でないことを確かめます。
    func testIsNotEmptyWhenAnythingToShow() {
        let bannerOnly = Fixture.state(phase: .idle, failureKey: "telemetry.disconnected.test")
        let samplesOnly = Fixture.state(phase: .paused, samples: samples)
        let retry = Fixture.state(phase: .failed, endpoint: Fixture.endpoint, vehicle: Fixture.registeredVehicle)

        XCTAssertFalse(LiveTelemetryPanelContent(state: bannerOnly).isEmpty)
        XCTAssertFalse(LiveTelemetryPanelContent(state: samplesOnly).isEmpty)
        XCTAssertFalse(LiveTelemetryPanelContent(state: retry).isEmpty)
    }
}
