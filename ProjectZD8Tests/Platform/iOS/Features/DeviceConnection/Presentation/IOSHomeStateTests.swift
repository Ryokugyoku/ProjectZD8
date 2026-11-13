#if os(iOS)
import XCTest
@testable import ProjectZD8

/// iOS HOMEのアダプター表示状態への変換を検証します。
final class IOSHomeStateTests: XCTestCase {
    /// デフォルト未設定時に設定を要求する状態となることを検証します。
    ///
    /// 責務: 空のiOS設定状態がHOMEでデフォルト未設定として表現されることを確認します。
    func testEmptySettingsRequireDefaultAdapterSetup() {
        let state = IOSHomeState(settingsState: IOSSettingsState())

        XCTAssertEqual(state.defaultAdapterAvailability, .notConfigured)
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
        var settingsState = IOSSettingsState()
        settingsState.defaultAdapterPreference = DefaultAdapterPreference(adapter: adapter)
        settingsState.selectedAdapters[.primary] = adapter

        let state = IOSHomeState(settingsState: settingsState)

        XCTAssertTrue(state.defaultAdapterAvailability.hasDefaultAdapter)
        XCTAssertEqual(state.defaultAdapterAvailability.displayName, "Saved Adapter")
        XCTAssertTrue(state.defaultAdapterAvailability.isDetected)
    }

    /// Bluetoothデモを保存・検出したHOMEが接続終端を公開することを検証します。
    ///
    /// 責務: iOS HOMEの接続ボタンが選択済みBluetoothデモを通常の接続終端へ変換できることを確認します。
    func testSelectedBluetoothDemoExposesConnectionEndpoint() {
        let adapter = DemoOBDAdapter.bluetoothCandidate
        var settingsState = IOSSettingsState()
        settingsState.defaultAdapterPreference = DefaultAdapterPreference(adapter: adapter)
        settingsState.selectedAdapters[.primary] = adapter

        let state = IOSHomeState(settingsState: settingsState)

        XCTAssertEqual(state.defaultAdapterAvailability.connectionEndpoint, OBDConnectionEndpoint(adapter: adapter))
        XCTAssertEqual(state.defaultAdapterAvailability.connectionEndpoint?.transport, .bluetoothLowEnergy)
        XCTAssertEqual(state.defaultAdapterAvailability.connectionEndpoint?.systemIdentifier, adapter.systemIdentifier)
    }

    /// 保存済み候補が現在未検出ならBluetooth接続終端を公開しません。
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
        var settingsState = IOSSettingsState()
        settingsState.defaultAdapterPreference = DefaultAdapterPreference(adapter: adapter)

        let state = IOSHomeState(settingsState: settingsState)

        XCTAssertEqual(
            state.defaultAdapterAvailability,
            .notDetected(displayName: "Saved Adapter")
        )
        XCTAssertNil(state.defaultAdapterAvailability.connectionEndpoint)
    }

    /// PID取得中はHOMEが切断操作を公開することを検証します。
    ///
    /// 責務: LiveTelemetryの取得段階をiOS HOMEの接続中状態へ変換することを確認します。
    func testReadingTelemetryPresentsActiveConnection() {
        var telemetryState = LiveTelemetryState()
        telemetryState.phase = .reading

        let state = IOSHomeState(
            settingsState: IOSSettingsState(),
            liveTelemetryState: telemetryState
        )

        XCTAssertTrue(state.isConnectionActive)
        XCTAssertFalse(state.isDisconnecting)
    }
}
#endif
