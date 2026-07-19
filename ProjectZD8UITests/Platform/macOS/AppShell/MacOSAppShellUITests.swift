#if os(macOS)
import XCTest

/// macOS AppShellが所有する起動時の表示動作を検証します。
final class MacOSAppShellUITests: XCTestCase {
    /// macOSアプリケーションの起動時にmacOS専用ルートレイアウトが表示されることを検証します。
    ///
    /// 責務: プロセスエントリーポイントからmacOS AppShellへ到達できることを確認します。
    @MainActor
    func testLaunchShowsMacOSAppShell() {
        let application = XCUIApplication()

        application.launch()

        XCTAssertTrue(application.descendants(matching: .any)["macos-app-shell"].waitForExistence(timeout: 5))
    }

    /// macOSサイドバーが要求されたすべての遷移先を公開することを検証します。
    ///
    /// 責務: macOS AppShellが4件のナビゲーション操作を表示することを確認します。
    @MainActor
    func testSidebarShowsEveryRequestedDestination() {
        let application = XCUIApplication()
        application.launch()

        XCTAssertTrue(application.buttons["macos-sidebar-home"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["macos-sidebar-liveLog"].exists)
        XCTAssertTrue(application.buttons["macos-sidebar-maintenance"].exists)
        XCTAssertTrue(application.buttons["macos-sidebar-settings"].exists)
    }

    /// macOSサイドバーの遷移先を操作するとコンテンツ領域が切り替わることを検証します。
    ///
    /// 責務: 1件のサイドバー選択に対応するmacOS遷移先が描画されることを確認します。
    @MainActor
    func testSidebarSelectionShowsMatchingDestination() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))

        settingsButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-screen"].waitForExistence(timeout: 2))
    }

    /// デフォルト未設定のHOME操作が押すたびに案内され、手動でも再遷移できることを検証します。
    ///
    /// 責務: macOS HOMEの設定ボタンによる2回の案内と通常の設定サイドバー遷移を同じ操作フローで確認します。
    @MainActor
    func testHomeSetupActionShowsAdapterSettings() {
        let application = XCUIApplication()
        application.launchArguments += ["-deviceConnection.defaultAdapter", ""]
        application.launch()

        let setupButton = application.buttons["macos-home-setup-adapter"]
        XCTAssertTrue(setupButton.waitForExistence(timeout: 5))
        setupButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-adapter-card"].exists)

        application.buttons["macos-sidebar-home"].click()
        XCTAssertTrue(application.descendants(matching: .any)["macos-home-screen"].waitForExistence(timeout: 2))
        application.buttons["macos-sidebar-settings"].click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-adapter-card"].exists)

        application.buttons["macos-sidebar-home"].click()
        let secondSetupButton = application.buttons["macos-home-setup-adapter"]
        XCTAssertTrue(secondSetupButton.waitForExistence(timeout: 2))
        secondSetupButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-adapter-card"].exists)
    }

    /// 設定画面が要求された設定カテゴリとアダプター選択導線を公開することを検証します。
    ///
    /// 責務: macOS設定画面にアダプター設定と将来のストレージ設定が表示されることを確認します。
    @MainActor
    func testSettingsShowsRequestedConfigurationCategories() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-language"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-adapter-primary"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-adapter-secondary"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-storage-coming-soon"].exists)
    }

    /// プライマリーアダプターの選択操作から接続方式別の候補画面へ進めることを検証します。
    ///
    /// 責務: macOS設定画面がUSBとBluetoothを選べるアダプター探索モーダルを表示することを確認します。
    @MainActor
    func testPrimaryAdapterSelectionShowsTransportModes() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-screen"].waitForExistence(timeout: 2))
        let primaryAdapterButton = application.buttons["プライマリーアダプター"]
        XCTAssertTrue(primaryAdapterButton.waitForExistence(timeout: 2))
        primaryAdapterButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-primary-adapter-selection"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.radioButtons["USB"].exists)
        XCTAssertTrue(application.radioButtons["Bluetooth"].exists)
    }

    /// セカンダリーアダプターでも共通の接続方式選択画面へ進めることを検証します。
    ///
    /// 責務: 受信専用セカンダリーがUSBとBluetoothを持つ共通候補モーダルを表示することを確認します。
    @MainActor
    func testSecondaryAdapterSelectionShowsSharedTransportModes() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let secondaryAdapterButton = application.buttons["セカンダリーアダプター"]
        XCTAssertTrue(secondaryAdapterButton.waitForExistence(timeout: 2))
        secondaryAdapterButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-secondary-adapter-selection"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.radioButtons["USB"].exists)
        XCTAssertTrue(application.radioButtons["Bluetooth"].exists)
    }

    /// Bluetooth探索へ切り替えた直後も選択画面をキャンセルできることを検証します。
    ///
    /// 責務: Bluetoothシステム探索がmacOS設定モーダルの操作をブロックしないことを確認します。
    @MainActor
    func testBluetoothDiscoveryKeepsSelectionModalResponsive() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let primaryAdapterButton = application.buttons["プライマリーアダプター"]
        XCTAssertTrue(primaryAdapterButton.waitForExistence(timeout: 2))
        primaryAdapterButton.click()

        let bluetoothMode = application.radioButtons["Bluetooth"]
        XCTAssertTrue(bluetoothMode.waitForExistence(timeout: 3))
        bluetoothMode.click()

        let cancelButton = application.buttons["キャンセル"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 1))
        cancelButton.click()
        XCTAssertFalse(application.descendants(matching: .any)["macos-primary-adapter-selection"].exists)
    }

    /// 言語と外観の選択が現在のAppShell表示へ反映されることを検証します。
    ///
    /// 責務: macOS設定画面の表示設定操作が現在のAppShell表示状態を更新することを確認します。
    @MainActor
    func testSettingsAppliesLanguageAndAppearanceToCurrentAppShell() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let englishOption = application.radioButtons["English"]
        XCTAssertTrue(englishOption.waitForExistence(timeout: 2))
        englishOption.click()
        XCTAssertEqual(application.buttons["macos-sidebar-home"].label, "Home")

        let darkAppearance = application.buttons["macos-settings-appearance-dark"]
        XCTAssertTrue(darkAppearance.exists)
        darkAppearance.click()
        XCTAssertTrue(darkAppearance.isSelected)
    }
}
#endif
