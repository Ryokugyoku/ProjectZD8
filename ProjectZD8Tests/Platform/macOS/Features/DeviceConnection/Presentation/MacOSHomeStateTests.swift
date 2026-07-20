#if os(macOS)
import XCTest
@testable import ProjectZD8

/// macOS HOMEのアダプター表示状態への変換を検証します。
final class MacOSHomeStateTests: XCTestCase {
    /// デフォルト未設定時に設定を要求する状態となることを検証します。
    ///
    /// 責務: 空の設定状態がHOMEでデフォルト未設定として表現されることを確認します。
    func testEmptySettingsRequireDefaultAdapterSetup() {
        let state = MacOSHomeState(settingsState: MacOSSettingsState())

        XCTAssertEqual(state.defaultAdapterAvailability, .notConfigured)
    }

    /// 保存済みデフォルトと検出済みプライマリーが一致する状態を検証します。
    ///
    /// 責務: 保存設定と検出結果の一致がHOMEの検出済み表示へ変換されることを確認します。
    func testMatchingPrimaryAdapterIsPresentedAsDetectedDefault() {
        let adapter = DiscoveredAdapter(
            id: "saved",
            transportMode: .usb,
            displayName: "Saved Adapter",
            systemIdentifier: "/dev/cu.saved",
            isConnected: false
        )
        var settingsState = MacOSSettingsState()
        settingsState.defaultAdapterPreference = DefaultAdapterPreference(adapter: adapter)
        settingsState.selectedAdapters[.primary] = adapter

        let state = MacOSHomeState(settingsState: settingsState)

        XCTAssertTrue(state.defaultAdapterAvailability.hasDefaultAdapter)
        XCTAssertEqual(state.defaultAdapterAvailability.displayName, "Saved Adapter")
        XCTAssertTrue(state.defaultAdapterAvailability.isDetected)
        XCTAssertEqual(state.connectionEndpoint?.systemIdentifier, "/dev/cu.saved")
    }

    /// 保存済み候補が現在未検出なら古いシリアル終端を使用しません。
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
        var settingsState = MacOSSettingsState()
        settingsState.defaultAdapterPreference = DefaultAdapterPreference(adapter: adapter)

        let state = MacOSHomeState(settingsState: settingsState)

        XCTAssertEqual(
            state.defaultAdapterAvailability,
            .notDetected(displayName: "Saved Adapter")
        )
        XCTAssertNil(state.connectionEndpoint)
    }

    /// 検出済みBluetooth候補はmacOSのシリアル接続終端として公開しません。
    ///
    /// 責務: macOS HOMEが検証済みUSB経路以外の接続方式を有効化しないことを確認します。
    func testDetectedBluetoothAdapterDoesNotExposeSerialConnectionEndpoint() {
        let adapter = DiscoveredAdapter(
            id: "bluetooth",
            transportMode: .bluetooth,
            displayName: "Bluetooth Adapter",
            systemIdentifier: "bluetooth",
            isConnected: false
        )
        var settingsState = MacOSSettingsState()
        settingsState.defaultAdapterPreference = DefaultAdapterPreference(adapter: adapter)
        settingsState.selectedAdapters[.primary] = adapter

        let state = MacOSHomeState(settingsState: settingsState)

        XCTAssertTrue(state.defaultAdapterAvailability.isDetected)
        XCTAssertNil(state.connectionEndpoint)
    }

    /// 通信資源終了中はHOMEが切断操作を無効化する状態を公開します。
    ///
    /// 責務: LiveTelemetryの終了段階をmacOS HOMEの切断処理中状態へ変換することを確認します。
    func testStoppingTelemetryPresentsDisconnectingConnection() {
        var telemetryState = LiveTelemetryState()
        telemetryState.phase = .stopping

        let state = MacOSHomeState(
            settingsState: MacOSSettingsState(),
            liveTelemetryState: telemetryState
        )

        XCTAssertTrue(state.isConnectionActive)
        XCTAssertTrue(state.isDisconnecting)
    }

    /// BRZ Beta取得中をHOME表示状態へ公開します。
    ///
    /// 責務: 周期取得方式がmacOS HOMEのBeta表示フラグへ変換されることを確認します。
    func testBRZPeriodicModePresentsBetaConnection() {
        var telemetryState = LiveTelemetryState()
        telemetryState.phase = .loaded
        telemetryState.acquisitionMode = .brzBetaPeriodic

        let state = MacOSHomeState(
            settingsState: MacOSSettingsState(),
            liveTelemetryState: telemetryState
        )

        XCTAssertTrue(state.isBRZBetaActive)
    }

    /// BRZ Betaの明示同意待ちをHOMEへ公開します。
    ///
    /// 責務: Applicationの判断待ち段階がmacOS HOMEの警告表示条件へ変換されることを確認します。
    func testBRZConsentPhasePresentsRiskDecision() {
        var telemetryState = LiveTelemetryState()
        telemetryState.phase = .awaitingBRZBetaConsent

        let state = MacOSHomeState(
            settingsState: MacOSSettingsState(),
            liveTelemetryState: telemetryState
        )

        XCTAssertTrue(state.requiresBRZBetaConsent)
        XCTAssertFalse(state.isBRZBetaActive)
    }
}
#endif
