#if os(macOS)
import XCTest
@testable import ProjectZD8

/// macOS HOMEのアダプター表示状態と、USBに限る接続先の規則による共通のホーム表示状態への変換を検証します。
@MainActor
final class MacOSHomeStateTests: XCTestCase {
    private typealias Fixture = HomeScreenTestFixture

    /// デフォルト未設定時に設定を要求する状態となることを検証します。
    ///
    /// 責務: 空の設定状態がHOMEでデフォルト未設定として表現され、カードが設定操作を出すことを確認します。
    func testEmptySettingsRequireDefaultAdapterSetup() {
        let state = MacOSHomeState(settingsState: MacOSSettingsState())

        XCTAssertEqual(state.defaultAdapterAvailability, .notConfigured)
        XCTAssertNil(state.connectionEndpoint)
        XCTAssertEqual(state.screen.layout, .adapterSetup)
        XCTAssertNil(state.screen.sessionHeader)
        XCTAssertEqual(state.screen.adapterCard.primaryAction, .setupAdapter)
    }

    /// 保存済みデフォルトと検出済みUSBプライマリーが一致する状態を検証します。
    ///
    /// 責務: 保存設定と検出結果の一致が検出済み表示と、その接続先を渡す接続操作へ変換されることを確認します。
    func testMatchingPrimaryAdapterIsPresentedAsDetectedDefault() {
        let adapter = DiscoveredAdapter(
            id: "saved",
            transportMode: .usb,
            displayName: "Saved Adapter",
            systemIdentifier: "/dev/cu.saved",
            isConnected: false
        )

        let state = MacOSHomeState(settingsState: settings(saved: adapter, detected: adapter))

        XCTAssertTrue(state.defaultAdapterAvailability.hasDefaultAdapter)
        XCTAssertEqual(state.defaultAdapterAvailability.displayName, "Saved Adapter")
        XCTAssertTrue(state.defaultAdapterAvailability.isDetected)
        XCTAssertEqual(state.connectionEndpoint?.systemIdentifier, "/dev/cu.saved")
        XCTAssertEqual(state.screen.adapterCard.primaryAction, .connect(OBDConnectionEndpoint(adapter: adapter)))
    }

    /// 保存済み候補が現在未検出なら古いシリアル終端を使用せず、設定操作を出します。
    ///
    /// 責務: 保存設定だけが残る状態を接続不能なHOME状態へ変換することを確認します。
    func testSavedButUndetectedAdapterDoesNotExposeConnectionEndpoint() {
        let adapter = DiscoveredAdapter(
            id: "saved",
            transportMode: .usb,
            displayName: "Saved Adapter",
            systemIdentifier: "/dev/cu.stale",
            isConnected: false
        )

        let state = MacOSHomeState(settingsState: settings(saved: adapter, detected: nil))

        XCTAssertEqual(state.defaultAdapterAvailability, .notDetected(displayName: "Saved Adapter"))
        XCTAssertNil(state.connectionEndpoint)
        XCTAssertEqual(state.screen.adapterCard.primaryAction, .setupAdapter)
    }

    /// 検出済みBluetooth候補はmacOSのシリアル接続終端として公開せず、接続先なしの接続操作にします。
    ///
    /// 責務: USB以外は検出済みでも `screen.adapterCard.primaryAction` が `.connect(nil)` になることを確認します。
    func testDetectedBluetoothAdapterDoesNotExposeSerialConnectionEndpoint() {
        let adapter = DiscoveredAdapter(
            id: "bluetooth",
            transportMode: .bluetooth,
            displayName: "Bluetooth Adapter",
            systemIdentifier: "bluetooth",
            isConnected: false
        )

        let state = MacOSHomeState(settingsState: settings(saved: adapter, detected: adapter))

        XCTAssertTrue(state.defaultAdapterAvailability.isDetected)
        XCTAssertNil(state.connectionEndpoint)
        XCTAssertTrue(state.screen.adapterCard.isDetected)
        XCTAssertEqual(state.screen.adapterCard.primaryAction, .connect(nil))
    }

    /// 通信資源の終了中は接続中の配置のまま切断操作を無効にすることを検証します。
    ///
    /// 責務: 終了段階が `sessionHeader.isDisconnectEnabled == false` に変換されることを確認します。
    func testStoppingTelemetryPresentsDisconnectingConnection() throws {
        let state = MacOSHomeState(
            settingsState: MacOSSettingsState(),
            liveTelemetryState: Fixture.telemetry(phase: .stopping, vehicle: .unregistered)
        )

        XCTAssertEqual(state.screen.layout, .connectedSession)
        let header = try XCTUnwrap(state.screen.sessionHeader)
        XCTAssertFalse(header.isDisconnectEnabled)
        XCTAssertEqual(header.vehicle, .unregistered)
        XCTAssertEqual(header.recording, .notRecording)
    }

    /// PID取得中はHOMEが接続中の配置になり、記録中のセッションと登録車両を見出しに出すことを検証します。
    ///
    /// 責務: 取得段階・`activeSession`・`vehicles` が `screen.sessionHeader` に反映されることを確認します。
    func testReadingTelemetryPresentsConnectedSessionHeader() throws {
        let vehicleID = VehicleID()

        let state = MacOSHomeState(
            settingsState: MacOSSettingsState(),
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

    /// 失敗段階は記録中のセッションがあってもアダプター設定の配置で見出しを出さないことを検証します。
    ///
    /// 責務: 接続していない段階で `sessionHeader` が `nil` になることを確認します。
    func testFailedTelemetryKeepsAdapterSetupLayout() {
        let state = MacOSHomeState(
            settingsState: MacOSSettingsState(),
            liveTelemetryState: Fixture.telemetry(phase: .failed),
            activeSession: Fixture.session(vehicleName: "BRZ")
        )

        XCTAssertEqual(state.screen.layout, .adapterSetup)
        XCTAssertNil(state.screen.sessionHeader)
    }

    /// 保存済みと検出済みのアダプターを指定したmacOS設定状態を作ります。
    ///
    /// 責務: デフォルト設定とプライマリーの検出結果を揃えた設定状態を返します。
    /// - Parameters:
    ///   - saved: デフォルトとして保存するアダプター。
    ///   - detected: プライマリーとして検出済みのアダプター。未検出なら `nil`。
    /// - Returns: 作った設定状態。
    private func settings(saved: DiscoveredAdapter, detected: DiscoveredAdapter?) -> MacOSSettingsState {
        var settingsState = MacOSSettingsState()
        settingsState.defaultAdapterPreference = DefaultAdapterPreference(adapter: saved)
        settingsState.selectedAdapters[.primary] = detected
        return settingsState
    }
}
#endif
