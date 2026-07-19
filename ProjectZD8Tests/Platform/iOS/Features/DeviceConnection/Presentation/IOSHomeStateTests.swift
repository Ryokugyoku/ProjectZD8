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

        XCTAssertFalse(state.hasDefaultAdapter)
        XCTAssertNil(state.defaultAdapterName)
        XCTAssertFalse(state.isDefaultAdapterDetected)
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

        XCTAssertTrue(state.hasDefaultAdapter)
        XCTAssertEqual(state.defaultAdapterName, "Saved Adapter")
        XCTAssertTrue(state.isDefaultAdapterDetected)
    }
}
#endif
