#if os(iOS)
import XCTest

/// iOS AppShellが所有する起動とナビゲーションの表示動作を検証します。
final class IOSAppShellUITests: XCTestCase {
    /// iOSアプリケーションの起動時にiOS専用ルートレイアウトが表示されることを検証します。
    ///
    /// 責務: プロセスエントリーポイントからiOS AppShellへ到達できることを確認します。
    @MainActor
    func testLaunchShowsIOSAppShell() {
        let application = XCUIApplication.authenticatedProjectZD8()

        application.launch()

        XCTAssertTrue(application.descendants(matching: .any)["ios-app-shell"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Home-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// iOS下部ナビゲーションが主要タブと標準のその他導線を公開することを検証します。
    ///
    /// 責務: iOS AppShellが4件の主要タブとGarage・設定を含む標準のその他一覧を表示することを確認します。
    @MainActor
    func testTabBarShowsEveryRequestedDestination() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        let tabBar = application.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.isHittable)
        XCTAssertEqual(tabBar.buttons.count, 5)
        for index in 0..<4 {
            XCTAssertTrue(tabBar.buttons.element(boundBy: index).isHittable)
        }

        let moreTab = tabBar.buttons.element(boundBy: 4)
        XCTAssertTrue(moreTab.exists)
        XCTAssertTrue(moreTab.isHittable)
        moreTab.tap()

        XCTAssertTrue(application.descendants(matching: .any)["Garage"].exists)
        XCTAssertTrue(["設定", "Settings", "Ajustes"].contains {
            application.descendants(matching: .any)[$0].exists
        })
    }

    /// 下部ナビゲーションの整備操作でiPhone専用整備画面へ切り替わることを検証します。
    ///
    /// 責務: 整備タブの選択がiPhone向け車両別整備画面を表示することを確認します。
    @MainActor
    func testMaintenanceTabShowsIOSMaintenanceScreen() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-maintenance",
            labels: ["整備", "Service", "Servicio"]
        ))

        XCTAssertTrue(application.descendants(matching: .any)["ios-maintenance"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Maintenance-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// 下部ナビゲーションのGarage操作でiOS専用車両一覧へ切り替わることを検証します。
    ///
    /// 責務: Garageタブの選択がiOS車両管理画面を表示することを確認します。
    @MainActor
    func testGarageTabShowsIOSGarageScreen() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-garage",
            labels: ["Garage", "Garaje"]
        ))

        XCTAssertTrue(application.descendants(matching: .any)["ios-garage-screen"].waitForExistence(timeout: 3))
        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Garage-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// 下部ナビゲーションの履歴操作でiOS専用接続履歴へ切り替わることを検証します。
    ///
    /// 責務: 履歴タブの選択が更新可能なiPhone向け接続履歴画面を表示することを確認します。
    @MainActor
    func testHistoryTabShowsIOSConnectionHistoryScreen() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-history",
            labels: ["履歴", "History", "Historial"]
        ))

        XCTAssertTrue(application.descendants(matching: .any)["ios-connection-history"].waitForExistence(timeout: 3))
    }

    /// デフォルト未設定のHOME操作が押すたびに案内され、手動でも再遷移できることを検証します。
    ///
    /// 責務: iPhone HOMEの設定ボタンによる2回の案内と通常の設定タブ遷移を同じ操作フローで確認します。
    @MainActor
    func testHomeSetupAdapterShowsTargetSettingsCard() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launchArguments += ["-deviceConnection.defaultAdapter", ""]
        application.launch()

        let setupButton = application.buttons["ios-home-setup-adapter"]
        XCTAssertTrue(setupButton.waitForExistence(timeout: 5))

        let homeScreenshot = XCTAttachment(screenshot: application.screenshot())
        homeScreenshot.name = "iPhone-Home-Adapter-Setup"
        homeScreenshot.lifetime = .keepAlways
        add(homeScreenshot)

        setupButton.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-adapter-card"].waitForExistence(timeout: 2))

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Settings-Adapter-Attention"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-home",
            labels: ["ホーム", "Home", "Inicio"]
        ))
        XCTAssertTrue(application.descendants(matching: .any)["ios-home-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-settings",
            labels: ["設定", "Settings", "Ajustes"]
        ))

        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-adapter-card"].exists)

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-home",
            labels: ["ホーム", "Home", "Inicio"]
        ))
        let secondSetupButton = application.buttons["ios-home-setup-adapter"]
        XCTAssertTrue(secondSetupButton.waitForExistence(timeout: 2))
        secondSetupButton.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-adapter-card"].exists)
    }

    /// 下部ナビゲーションの設定操作でiOS設定画面へ切り替わることを検証します。
    ///
    /// 責務: 設定タブの選択に対応するiOS設定画面が描画されることを確認します。
    @MainActor
    func testSettingsTabShowsSettingsScreen() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-settings",
            labels: ["設定", "Settings", "Ajustes"]
        ))

        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-screen"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["ios-settings-language"].exists)
        XCTAssertTrue(application.buttons["ios-settings-appearance-system"].exists)

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Settings-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// iOS設定画面の外観選択が明示指定からシステム追従へ戻ることを検証します。
    ///
    /// 責務: ダークなシステム外観でライトを選んだ後にシステム追従を再選択できることを確認します。
    @MainActor
    func testSettingsAppliesAppearanceToCurrentAppShell() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-settings",
            labels: ["設定", "Settings", "Ajustes"]
        ))

        let lightAppearance = application.buttons["ios-settings-appearance-light"]
        XCTAssertTrue(lightAppearance.waitForExistence(timeout: 2))
        lightAppearance.tap()
        XCTAssertTrue(lightAppearance.isSelected)

        let systemAppearance = application.buttons["ios-settings-appearance-system"]
        systemAppearance.tap()
        XCTAssertTrue(systemAppearance.isSelected)

        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "iPhone-Settings-System-Dark-After-Light"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// iOS設定画面が長い翻訳と明るい外観でも操作可能なことを検証します。
    ///
    /// 責務: スペイン語と明るい外観を選択した設定画面が表示を継続することを確認します。
    @MainActor
    func testSettingsSupportsSpanishInLightAppearance() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-settings",
            labels: ["設定", "Settings", "Ajustes"]
        ))

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

    /// アカウント削除開始操作が最初の警告を表示することを検証します。
    ///
    /// 責務: iOS設定画面の削除開始ボタンが未起動の削除フローへ入力を渡せることを確認します。
    @MainActor
    func testAccountDeletionStartPresentsWarning() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-settings",
            labels: ["設定", "Settings", "Ajustes"]
        ))

        let deleteStart = application.buttons["ios-account-delete-start"]
        for _ in 0..<4 where !deleteStart.exists {
            application.descendants(matching: .any)["ios-settings-screen"].swipeUp()
        }
        XCTAssertTrue(deleteStart.waitForExistence(timeout: 2))
        deleteStart.tap()

        let nextButton = ["次へ", "Next", "Siguiente"]
            .map { application.buttons[$0] }
            .first { $0.waitForExistence(timeout: 1) }
        XCTAssertNotNil(nextButton)
    }

    /// アカウント削除が2段階確認後にログイン画面へ戻ることを検証します。
    ///
    /// 責務: iOS設定画面の警告、削除事項、最終削除、ログアウト遷移を一続きで確認します。
    @MainActor
    func testAccountDeletionShowsWarningAndItemsThenReturnsToLogin() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-settings",
            labels: ["設定", "Settings", "Ajustes"]
        ))

        let deleteStart = application.buttons["ios-account-delete-start"]
        for _ in 0..<4 where !deleteStart.exists {
            application.descendants(matching: .any)["ios-settings-screen"].swipeUp()
        }
        XCTAssertTrue(deleteStart.waitForExistence(timeout: 2))
        deleteStart.tap()

        let nextButton = ["次へ", "Next", "Siguiente"]
            .map { application.buttons[$0] }
            .first { $0.waitForExistence(timeout: 1) }
        XCTAssertNotNil(nextButton)
        nextButton?.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-account-delete-review"].waitForExistence(timeout: 2))
        let confirmButton = application.buttons["ios-account-delete-confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 2))
        confirmButton.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-login-screen"].waitForExistence(timeout: 5))
    }

    /// 両アダプター行から共通のBluetooth専用選択画面へ進めることを検証します。
    ///
    /// 責務: iPhone設定画面の両スロットがUSB切替なしでキャンセル可能なBLE選択導線を共有することを確認します。
    @MainActor
    func testAdapterRowsShowSharedCancelableBluetoothOnlySelection() {
        let application = XCUIApplication.authenticatedProjectZD8()
        addUIInterruptionMonitor(withDescription: "Bluetooth Permission") { alert in
            let permissionButtons = ["許可", "Allow", "Permitir"]
            for title in permissionButtons where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-settings",
            labels: ["設定", "Settings", "Ajustes"]
        ))

        let primaryAdapter = application.buttons.matching(
            identifier: "ios-settings-adapter-card"
        ).element(boundBy: 0)
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

        let secondaryAdapter = application.buttons.matching(
            identifier: "ios-settings-adapter-card"
        ).element(boundBy: 1)
        XCTAssertTrue(secondaryAdapter.waitForExistence(timeout: 2))
        secondaryAdapter.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-adapter-selection-secondary"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.descendants(matching: .any)["ios-settings-adapter-unavailable"].exists)

        let secondaryCancelButton = application.buttons["ios-adapter-selection-cancel"]
        XCTAssertTrue(secondaryCancelButton.waitForExistence(timeout: 2))
        secondaryCancelButton.tap()
        XCTAssertFalse(application.descendants(matching: .any)["ios-adapter-selection-secondary"].waitForExistence(timeout: 1))
    }

    /// Bluetoothデモを選択してHOME接続から合成車両識別へ進めることを検証します。
    ///
    /// 責務: iPhoneの設定、デモ選択、保存、HOME接続、VIN確認までの利用者導線を一続きで確認します。
    @MainActor
    func testBluetoothDemoConnectsFromHomeWithoutPhysicalCommunication() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launchArguments += ["-deviceConnection.defaultAdapter", ""]
        addUIInterruptionMonitor(withDescription: "Bluetooth Permission") { alert in
            let permissionButtons = ["許可", "Allow", "Permitir"]
            for title in permissionButtons where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        application.launch()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-settings",
            labels: ["設定", "Settings", "Ajustes"]
        ))
        let primaryAdapter = application.buttons.matching(
            identifier: "ios-settings-adapter-card"
        ).firstMatch
        XCTAssertTrue(primaryAdapter.waitForExistence(timeout: 5))
        primaryAdapter.tap()
        application.tap()

        let demoCandidate = application.buttons["ios-adapter-candidate-bluetooth-low-energy:projectzd8-demo"]
        XCTAssertTrue(demoCandidate.waitForExistence(timeout: 6))
        demoCandidate.tap()

        let confirmButton = application.buttons["ios-adapter-confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 2))
        confirmButton.tap()

        XCTAssertTrue(application.selectAppShellTab(
            identifier: "ios-tab-home",
            labels: ["ホーム", "Home", "Inicio"]
        ))

        let connectButton = application.buttons["ios-home-connect"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 3))
        connectButton.tap()

        XCTAssertTrue(application.descendants(matching: .any)["ios-vehicle-registration"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.staticTexts["TESTZD8CXR0000001"].exists)
    }
}

/// iOS AppShell UIテスト用の認証済み起動構成を生成します。
private extension XCUIApplication {
    /// 指定されたAppShellタブを直接または標準のその他一覧から選択します。
    ///
    /// 責務: iPhoneの標準タブ上限に応じた1件の遷移先選択をUIテストへ提供します。
    /// - Parameters:
    ///   - identifier: タブ項目へ割り当てた安定アクセシビリティ識別子。
    ///   - labels: タブバーまたはその他一覧で遷移先を特定するローカライズ済み候補名。
    /// - Returns: 対象のタブまたはその他一覧項目を選択できた場合は `true`。
    @MainActor
    func selectAppShellTab(identifier: String, labels: [String]) -> Bool {
        let directTab = buttons[identifier]
        if directTab.waitForExistence(timeout: 1) {
            directTab.tap()
            return true
        }

        let tabBar = tabBars.firstMatch
        guard tabBar.waitForExistence(timeout: 2), tabBar.buttons.count > 4 else { return false }
        for label in labels {
            let localizedTab = tabBar.buttons[label]
            if localizedTab.exists {
                localizedTab.tap()
                return true
            }
        }
        tabBar.buttons.element(boundBy: 4).tap()

        for label in labels {
            let overflowItem = descendants(matching: .any)[label]
            if overflowItem.waitForExistence(timeout: 1) {
                overflowItem.tap()
                return true
            }
        }
        return false
    }

    /// 認証済みDebug起動引数を持つProject ZD8アプリを生成します。
    ///
    /// 責務: AppShell UIテストを実Apple認証から分離します。
    /// - Returns: 認証済みDebug起動を要求するUIテストアプリ。
    static func authenticatedProjectZD8() -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments.append("--ui-test-authenticated")
        return application
    }
}
#endif
