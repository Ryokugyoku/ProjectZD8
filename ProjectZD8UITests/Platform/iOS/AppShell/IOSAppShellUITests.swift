#if os(iOS)
import XCTest

/// iOS AppShellが所有する起動とナビゲーションの表示動作を検証します。
final class IOSAppShellUITests: XCTestCase {
    /// iOSアプリケーションの起動時にiOS専用ルートレイアウトが表示されることを検証します。
    ///
    /// 責務: プロセスエントリーポイントからiOS AppShellへ到達できることを確認します。
    @MainActor
    func testLaunchShowsIOSAppShell() {
        let application = XCUIApplication()

        application.launch()

        XCTAssertTrue(application.descendants(matching: .any)["ios-app-shell"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Home-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// iOS下部ナビゲーションが要求されたすべての遷移先を公開することを検証します。
    ///
    /// 責務: iOS AppShellが4件のタブ操作を表示することを確認します。
    @MainActor
    func testTabBarShowsEveryRequestedDestination() {
        let application = XCUIApplication()
        application.launch()

        XCTAssertTrue(application.buttons["ios-tab-home"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["ios-tab-liveLog"].exists)
        XCTAssertTrue(application.buttons["ios-tab-maintenance"].exists)
        XCTAssertTrue(application.buttons["ios-tab-settings"].exists)
    }

    /// 下部ナビゲーションの設定操作でiOS設定画面へ切り替わることを検証します。
    ///
    /// 責務: 設定タブの選択に対応するiOS設定画面が描画されることを確認します。
    @MainActor
    func testSettingsTabShowsSettingsScreen() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["ios-tab-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-language"].exists)
        XCTAssertTrue(application.buttons["ios-settings-appearance-system"].exists)

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Settings-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// iOS設定画面の外観選択が現在の表示状態へ反映されることを検証します。
    ///
    /// 責務: 1件の外観設定操作が選択済みのアクセシビリティ状態になることを確認します。
    @MainActor
    func testSettingsAppliesAppearanceToCurrentAppShell() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["ios-tab-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let darkAppearance = application.buttons["ios-settings-appearance-dark"]
        XCTAssertTrue(darkAppearance.waitForExistence(timeout: 2))
        darkAppearance.tap()

        XCTAssertTrue(darkAppearance.isSelected)
    }

    /// iOS設定画面が長い翻訳と明るい外観でも操作可能なことを検証します。
    ///
    /// 責務: スペイン語と明るい外観を選択した設定画面が表示を継続することを確認します。
    @MainActor
    func testSettingsSupportsSpanishInLightAppearance() {
        let application = XCUIApplication()
        application.launch()

        let settingsButton = application.buttons["ios-tab-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let spanishLanguage = application.buttons["Español"]
        XCTAssertTrue(spanishLanguage.waitForExistence(timeout: 2))
        spanishLanguage.tap()

        let lightAppearance = application.buttons["ios-settings-appearance-light"]
        XCTAssertTrue(lightAppearance.waitForExistence(timeout: 2))
        lightAppearance.tap()
        XCTAssertTrue(lightAppearance.isSelected)

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Settings-Spanish-Light"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// 両アダプター行から共通のBluetooth専用選択画面へ進めることを検証します。
    ///
    /// 責務: iPhone設定画面の両スロットがUSB切替なしでキャンセル可能なBLE選択導線を共有することを確認します。
    @MainActor
    func testAdapterRowsShowSharedCancelableBluetoothOnlySelection() {
        let application = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Bluetooth Permission") { alert in
            let permissionButtons = ["許可", "Allow", "Permitir"]
            for title in permissionButtons where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        application.launch()

        let settingsButton = application.buttons["ios-tab-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let primaryAdapter = application.buttons["ios-settings-adapter-primary"]
        XCTAssertTrue(primaryAdapter.waitForExistence(timeout: 2))
        primaryAdapter.tap()
        application.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-adapter-selection-primary"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.descendants(matching: .any)["ios-adapter-transport-mode"].exists)
        XCTAssertFalse(application.buttons["ios-adapter-transport-usb"].exists)

        let cancelButton = application.buttons["ios-adapter-selection-cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        cancelButton.tap()
        XCTAssertFalse(application.descendants(matching: .any)["ios-adapter-selection-primary"].waitForExistence(timeout: 1))

        let secondaryAdapter = application.buttons["ios-settings-adapter-secondary"]
        XCTAssertTrue(secondaryAdapter.waitForExistence(timeout: 2))
        secondaryAdapter.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-adapter-selection-secondary"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.descendants(matching: .any)["ios-settings-adapter-unavailable"].exists)

        let secondaryCancelButton = application.buttons["ios-adapter-selection-cancel"]
        XCTAssertTrue(secondaryCancelButton.waitForExistence(timeout: 2))
        secondaryCancelButton.tap()
        XCTAssertFalse(application.descendants(matching: .any)["ios-adapter-selection-secondary"].waitForExistence(timeout: 1))
    }
}
#endif
