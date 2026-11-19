#if os(iOS)
import XCTest
@testable import ProjectZD8

/// iOS HOMEのアダプター表示状態と、共通のホーム表示状態への変換を検証します。
@MainActor
final class IOSHomeStateTests: XCTestCase {
    private typealias Fixture = HomeScreenTestFixture

    /// デフォルト未設定時に設定を要求する状態となることを検証します。
    ///
    /// 責務: 空のiOS設定状態がHOMEでデフォルト未設定として表現され、カードが設定操作を出すことを確認します。
    func testEmptySettingsRequireDefaultAdapterSetup() {
        let state = IOSHomeState(settingsState: IOSSettingsState())

        XCTAssertEqual(state.defaultAdapterAvailability, .notConfigured)
        XCTAssertEqual(state.screen.layout, .adapterSetup)
        XCTAssertNil(state.screen.sessionHeader)
        XCTAssertEqual(state.screen.adapterCard.primaryAction, .setupAdapter)
    }

    /// 保存済みデフォルトと検出済みプライマリーが一致する状態を検証します。
    ///
    /// 責務: iOSの保存設定と検出結果の一致がHOMEの検出済み表示へ変換されることを確認します。
    func testMatchingPrimaryAdapterIsPresentedAsDetectedDefault() {
        let adapter = DiscoveredAdapter(
            id: "saved",
            transportMode: .bluetooth,
            displayName: "Saved Adapter",
            systemIdentifier: "saved",
            isConnected: false
        )

        let state = IOSHomeState(settingsState: settings(saved: adapter, detected: adapter))

        XCTAssertTrue(state.defaultAdapterAvailability.hasDefaultAdapter)
        XCTAssertEqual(state.defaultAdapterAvailability.displayName, "Saved Adapter")
        XCTAssertTrue(state.defaultAdapterAvailability.isDetected)
        XCTAssertEqual(state.screen.adapterCard.adapterName, "Saved Adapter")
        XCTAssertTrue(state.screen.adapterCard.isDetected)
    }

    /// Bluetoothデモを保存・検出したHOMEが接続終端をカードの接続操作へ渡すことを検証します。
    ///
    /// 責務: iOSの接続先が `defaultAdapterAvailability.connectionEndpoint` のまま `screen` の接続操作になることを確認します。
    func testSelectedBluetoothDemoExposesConnectionEndpoint() {
        let adapter = DemoOBDAdapter.bluetoothCandidate

        let state = IOSHomeState(settingsState: settings(saved: adapter, detected: adapter))

        let expected = OBDConnectionEndpoint(adapter: adapter)
        XCTAssertEqual(state.defaultAdapterAvailability.connectionEndpoint, expected)
        XCTAssertEqual(state.defaultAdapterAvailability.connectionEndpoint?.transport, .bluetoothLowEnergy)
        XCTAssertEqual(state.defaultAdapterAvailability.connectionEndpoint?.systemIdentifier, adapter.systemIdentifier)
        XCTAssertEqual(state.screen.adapterCard.primaryAction, .connect(expected))
    }

    /// 保存済み候補が現在未検出ならBluetooth接続終端を公開せず、設定操作を出します。
    ///
    /// 責務: 保存設定だけが残るiOS状態を再設定が必要な接続不能状態へ変換することを確認します。
    func testSavedButUndetectedAdapterDoesNotExposeConnectionEndpoint() {
        let adapter = DiscoveredAdapter(
            id: "saved",
            transportMode: .bluetooth,
            displayName: "Saved Adapter",
            systemIdentifier: "stale",
            isConnected: false
        )

        let state = IOSHomeState(settingsState: settings(saved: adapter, detected: nil))

        XCTAssertEqual(state.defaultAdapterAvailability, .notDetected(displayName: "Saved Adapter"))
        XCTAssertNil(state.defaultAdapterAvailability.connectionEndpoint)
        XCTAssertEqual(state.screen.adapterCard.primaryAction, .setupAdapter)
    }

    /// PID取得中はHOMEが接続中の配置になり、記録中のセッションと登録車両を見出しに出すことを検証します。
    ///
    /// 責務: 取得段階・`activeSession`・`vehicles` が `screen.sessionHeader` に反映されることを確認します。
    func testReadingTelemetryPresentsConnectedSessionHeader() throws {
        let vehicleID = VehicleID()

        let state = IOSHomeState(
            settingsState: IOSSettingsState(),
            liveTelemetryState: Fixture.telemetry(phase: .reading, vehicle: .registered(vehicleID, vehicleModelCode: nil)),
            activeSession: Fixture.session(),
            vehicles: [Fixture.vehicle(id: vehicleID, name: "BRZ")]
        )

        XCTAssertEqual(state.screen.layout, .connectedSession)
        let header = try XCTUnwrap(state.screen.sessionHeader)
        XCTAssertEqual(header.vehicle, .named("BRZ"))
        XCTAssertEqual(header.recording, .recording(startedAt: Fixture.startedAt))
        XCTAssertTrue(header.isDisconnectEnabled)
    }

    /// 通信資源の終了中は接続中の配置のまま切断操作を無効にすることを検証します。
    ///
    /// 責務: 終了段階が `sessionHeader.isDisconnectEnabled == false` に変換され、記録のないセッションを記録中と偽らないことを確認します。
    func testStoppingTelemetryDisablesDisconnect() throws {
        let state = IOSHomeState(
            settingsState: IOSSettingsState(),
            liveTelemetryState: Fixture.telemetry(phase: .stopping, vehicle: .unregistered)
        )

        XCTAssertEqual(state.screen.layout, .connectedSession)
        let header = try XCTUnwrap(state.screen.sessionHeader)
        XCTAssertFalse(header.isDisconnectEnabled)
        XCTAssertEqual(header.vehicle, .unregistered)
        XCTAssertEqual(header.recording, .notRecording)
    }

    /// 待機中は記録中のセッションがあってもアダプター設定の配置で見出しを出さないことを検証します。
    ///
    /// 責務: 接続していない段階で `sessionHeader` が `nil` になることを確認します。
    func testIdleTelemetryKeepsAdapterSetupLayout() {
        let state = IOSHomeState(
            settingsState: IOSSettingsState(),
            liveTelemetryState: Fixture.telemetry(phase: .idle),
            activeSession: Fixture.session(vehicleName: "BRZ")
        )

        XCTAssertEqual(state.screen.layout, .adapterSetup)
        XCTAssertNil(state.screen.sessionHeader)
    }

    /// 保存済みと検出済みのアダプターを指定したiOS設定状態を作ります。
    ///
    /// 責務: デフォルト設定とプライマリーの検出結果を揃えた設定状態を返します。
    /// - Parameters:
    ///   - saved: デフォルトとして保存するアダプター。
    ///   - detected: プライマリーとして検出済みのアダプター。未検出なら `nil`。
    /// - Returns: 作った設定状態。
    private func settings(saved: DiscoveredAdapter, detected: DiscoveredAdapter?) -> IOSSettingsState {
        var settingsState = IOSSettingsState()
        settingsState.defaultAdapterPreference = DefaultAdapterPreference(adapter: saved)
        settingsState.selectedAdapters[.primary] = detected
        return settingsState
    }
}
#endif
