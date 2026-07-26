#if os(iOS)
import XCTest

/// iOSログイン画面と免責事項の主要操作を検証します。
final class IOSLoginUITests: XCTestCase {
    /// ログイン画面が採用済みの製品名を表示することを検証します。
    ///
    /// 責務: iOS認証入口のブランド表示をRevTorque Insightへ固定します。
    @MainActor
    func testLoginShowsRevTorqueInsightBrand() {
        let application = XCUIApplication()
        application.launchArguments.append("--ui-test-signed-out")
        application.launch()

        XCTAssertTrue(application.staticTexts["RevTorque Insight"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Login-RevTorque-Insight-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// ログイン操作がApple認証より先に免責事項を表示することを検証します。
    ///
    /// 責務: iOSログイン導線の明示同意ゲートを実アカウントなしで確認します。
    @MainActor
    func testLoginPresentsDisclaimerBeforeAppleAuthorization() {
        let application = XCUIApplication()
        application.launchArguments.append("--ui-test-signed-out")
        application.launch()

        let loginButton = application.buttons["ios-auth-login"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5))
        loginButton.tap()

        XCTAssertTrue(
            application.descendants(matching: .any)["ios-auth-disclaimer"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(application.buttons["ios-auth-disclaimer-accept"].exists)

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Login-Disclaimer-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
#endif
