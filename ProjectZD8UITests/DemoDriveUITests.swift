#if os(iOS)
import XCTest

/// デモモードで、接続から記録・停止・ログ確認までの一連の操作ができることを確認します。
///
/// 環境変数 `UITEST_SCREENSHOT_DIR` を渡すと、各段階のスクリーンショットと画面階層をそのディレクトリへ書き出します。
final class DemoDriveUITests: XCTestCase {
    private var app: XCUIApplication!
    private var step = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
    }

    /// 責務: 現在の画面のスクリーンショットと階層を、指定ディレクトリがあれば書き出します。
    private func capture(_ name: String) {
        step += 1
        guard let directory = ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_DIR"] else { return }
        let base = URL(fileURLWithPath: directory).appendingPathComponent(String(format: "%02d-%@", step, name))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: base.appendingPathExtension("png"))
        try? app.debugDescription.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }

    /// 責務: 指定ラベルの要素が現れたらタップします。現れなければ失敗を記録します。
    @discardableResult
    private func tap(_ element: XCUIElement, _ name: String, timeout: TimeInterval = 8) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("\(name) が見つかりません")
            capture("missing-\(name)")
            return false
        }
        element.tap()
        return true
    }

    /// 責務: デモアダプターで接続し、記録画面・停止・ログ・ガレージまで到達できることを確認します。
    func testDemoDriveFlow() {
        capture("launch")
        tap(app.tabBars.buttons["設定"], "settings-tab")
        capture("settings")
        let demoToggle = app.switches["デモモード"]
        if demoToggle.waitForExistence(timeout: 5), (demoToggle.value as? String) == "0" {
            demoToggle.switches.firstMatch.exists ? demoToggle.switches.firstMatch.tap() : demoToggle.tap()
        }
        capture("settings-demo-on")

        tap(app.tabBars.buttons["ドライブ"], "drive-tab")
        let choose = app.buttons.matching(NSPredicate(format: "label IN {'アダプターを選んで接続', 'アダプターを選択'}")).firstMatch
        if choose.waitForExistence(timeout: 5) {
            choose.tap()
            capture("adapter-picker")
            let demoRow = app.staticTexts["RevTorque Demo"].firstMatch
            tap(demoRow, "demo-adapter", timeout: 20)
            capture("adapter-selected")
        } else {
            capture("adapter-already-set")
        }
        let connect = app.buttons.matching(NSPredicate(format: "label IN {'接続', '接続して記録を開始'}")).firstMatch
        if connect.waitForExistence(timeout: 5) { connect.tap() }
        capture("after-connect")

        let nameField = app.textFields["車両名"].firstMatch
        if nameField.waitForExistence(timeout: 20) {
            nameField.tap()
            nameField.typeText("Demo BRZ")
            capture("registration")
            tap(app.buttons["登録して開始"].firstMatch, "register")
        }
        let stop = app.buttons["停止"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 30), "記録画面に到達しません")
        sleep(12)
        capture("recording")
        app.swipeUp()
        capture("recording-scrolled")
        app.swipeDown()
        if stop.exists { stop.tap() }
        sleep(3)
        capture("stopped")

        tap(app.tabBars.buttons["ログ"], "logs-tab")
        sleep(2)
        capture("logs")
        let sessionRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'リクエスト'")).firstMatch
        if tap(sessionRow, "session-row") {
            sleep(1)
            capture("session-detail")
            if tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '分析'")).firstMatch, "analyze") {
                sleep(10)
                capture("analysis")
                let close = app.buttons["分析を閉じる"].firstMatch
                tap(close, "analysis-close")
                sleep(1)
            }
        }

        tap(app.tabBars.buttons["ガレージ"], "garage-tab")
        sleep(2)
        capture("garage")
        let vehicle = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Demo BRZ'")).firstMatch
        if tap(vehicle, "vehicle-card") {
            sleep(1)
            capture("vehicle-detail")
            app.swipeUp()
            capture("vehicle-detail-scrolled")
            if tap(app.buttons["PID収集設定"].firstMatch, "pid-settings") {
                sleep(1)
                capture("pid-settings")
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            if tap(app.buttons["整備記録"].firstMatch, "maintenance") {
                sleep(1)
                capture("maintenance")
            }
        }
    }
}
#endif
