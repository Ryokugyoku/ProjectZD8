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

        XCTAssertTrue(application.descendants(matching: .any)["macos-destination-settings"].waitForExistence(timeout: 2))
    }
}
#endif
