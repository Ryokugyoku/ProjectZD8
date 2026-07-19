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

    /// 設定画面が要求された設定カテゴリと未実装状態を公開することを検証します。
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
