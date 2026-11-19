import XCTest
@testable import ProjectZD8

/// 表示状態のフェーズからホームの配置を選び、アダプターカードとセッション見出しを組み立てる規則を検証します。
@MainActor
final class HomeScreenStateTests: XCTestCase {
    private typealias Fixture = HomeScreenTestFixture

    private let allPhases: [LiveTelemetryState.Phase] = [.idle, .reading, .loaded, .paused, .stopping, .failed]
    private let connectedPhases: Set<LiveTelemetryState.Phase> = [.reading, .loaded, .paused, .stopping]
    private let vehicleID = VehicleID()

    /// 指定フェーズのホーム状態を作ります。
    ///
    /// 責務: 検出済みアダプター・進行中セッション・名前付き車両を揃えた状態を返します。
    private func screen(phase: LiveTelemetryState.Phase) -> HomeScreenState {
        HomeScreenState(
            defaultAdapterAvailability: .detected(displayName: "My Adapter", endpoint: Fixture.endpoint),
            connectionEndpoint: Fixture.otherEndpoint,
            telemetry: Fixture.telemetry(phase: phase, vehicle: .registered(vehicleID, vehicleModelCode: nil)),
            activeSession: Fixture.session(),
            vehicles: [Fixture.vehicle(id: vehicleID, name: "BRZ")]
        )
    }

    /// 接続中の4フェーズはセッションの配置、待機と失敗はアダプター設定の配置です。
    ///
    /// 責務: 6フェーズの `layout` を確かめます。
    func testLayoutForEachPhase() {
        for phase in allPhases {
            let expected: HomeScreenLayout = connectedPhases.contains(phase) ? .connectedSession : .adapterSetup

            XCTAssertEqual(screen(phase: phase).layout, expected, "\(phase)")
        }
    }

    /// セッション見出しはセッションの配置の時だけ値を持ち、中身は同じ入力から作った見出しです。
    ///
    /// 責務: 接続中の4フェーズで `sessionHeader` の値を確かめます。
    func testSessionHeaderWhileConnected() throws {
        for phase in connectedPhases {
            let header = try XCTUnwrap(screen(phase: phase).sessionHeader, "\(phase)")

            XCTAssertEqual(header.vehicle, .named("BRZ"), "\(phase)")
            XCTAssertEqual(header.recording, .recording(startedAt: Fixture.startedAt), "\(phase)")
            XCTAssertEqual(header.isDisconnectEnabled, phase != .stopping, "\(phase)")
        }
    }

    /// 待機と失敗ではセッション見出しを持ちません。
    ///
    /// 責務: アダプター設定の配置で `sessionHeader` が nil であることを確かめます。
    func testNoSessionHeaderOutsideConnection() {
        for phase in [LiveTelemetryState.Phase.idle, .failed] {
            XCTAssertNil(screen(phase: phase).sessionHeader, "\(phase)")
        }
    }

    /// アダプターカードは配置に関係なく常に作り、渡された接続先を使います。
    ///
    /// 責務: 6フェーズで `adapterCard` の中身を確かめます。
    func testAdapterCardIsAlwaysBuilt() {
        for phase in allPhases {
            let card = screen(phase: phase).adapterCard

            XCTAssertEqual(card.adapterName, "My Adapter", "\(phase)")
            XCTAssertEqual(card.statusKey, "home.adapter.detected", "\(phase)")
            XCTAssertEqual(card.primaryAction, .connect(Fixture.otherEndpoint), "\(phase)")
        }
    }

    /// 未設定のアダプターでも、カードは設定操作として作ります。
    ///
    /// 責務: availability が notConfigured の時の `adapterCard` を確かめます。
    func testAdapterCardForNotConfigured() {
        let state = HomeScreenState(
            defaultAdapterAvailability: .notConfigured,
            connectionEndpoint: nil,
            telemetry: Fixture.telemetry(phase: .idle),
            activeSession: nil,
            vehicles: []
        )

        XCTAssertNil(state.adapterCard.adapterName)
        XCTAssertEqual(state.adapterCard.primaryAction, .setupAdapter)
        XCTAssertEqual(state.layout, .adapterSetup)
    }
}
