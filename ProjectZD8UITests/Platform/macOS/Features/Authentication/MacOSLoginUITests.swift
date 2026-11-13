#if os(macOS)
import XCTest

/// macOSログイン画面と免責事項の主要操作を検証します。
final class MacOSLoginUITests: XCTestCase {
    /// ログイン画面が採用済みの製品名を表示することを検証します。
    ///
    /// 責務: macOS認証入口のブランド表示をRevTorque Insightへ固定します。
    @MainActor
    func testLoginShowsRevTorqueInsightBrand() {
        let application = XCUIApplication()
        application.launchArguments.append("--ui-test-signed-out")
        application.launch()

        XCTAssertTrue(application.staticTexts["RevTorque Insight"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "Mac-Login-RevTorque-Insight-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// ログイン操作がApple認証より先に免責事項を表示することを検証します。
    ///
    /// 責務: macOSログイン導線の明示同意ゲートを実アカウントなしで確認します。
    @MainActor
    func testLoginPresentsDisclaimerBeforeAppleAuthorization() {
        let application = XCUIApplication()
        application.launchArguments.append("--ui-test-signed-out")
        application.launch()

        let loginButton = application.buttons["macos-auth-login"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
        loginButton.click()

        XCTAssertTrue(
            application.descendants(matching: .any)["macos-auth-disclaimer"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(application.buttons["macos-auth-disclaimer-accept"].exists)

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "Mac-Login-Disclaimer-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
#endif
