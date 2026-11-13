import XCTest

/// アプリが起動して最初の画面を表示できることだけを確認します。
final class AppLaunchUITests: XCTestCase {
    /// 責務: 起動直後にアプリが前面で動作していることを確認します。
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
