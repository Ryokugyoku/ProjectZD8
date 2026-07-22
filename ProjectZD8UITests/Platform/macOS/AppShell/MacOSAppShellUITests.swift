#if os(macOS)
import XCTest

/// macOS AppShellが所有する起動時の表示動作を検証します。
final class MacOSAppShellUITests: XCTestCase {
    /// macOSアプリケーションの起動時にmacOS専用ルートレイアウトが表示されることを検証します。
    ///
    /// 責務: プロセスエントリーポイントからmacOS AppShellへ到達できることを確認します。
    @MainActor
    func testLaunchShowsMacOSAppShell() {
        let application = XCUIApplication.authenticatedProjectZD8()

        application.launch()

        XCTAssertTrue(application.descendants(matching: .any)["macos-app-shell"].waitForExistence(timeout: 5))
    }

    /// macOSサイドバーが要求されたすべての遷移先を公開することを検証します。
    ///
    /// 責務: macOS AppShellがGarageを含む5件のナビゲーション操作を表示することを確認します。
    @MainActor
    func testSidebarShowsEveryRequestedDestination() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        XCTAssertTrue(application.buttons["macos-sidebar-home"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["macos-sidebar-liveLog"].exists)
        XCTAssertTrue(application.buttons["macos-sidebar-maintenance"].exists)
        XCTAssertTrue(application.buttons["macos-sidebar-garage"].exists)
        XCTAssertTrue(application.buttons["macos-sidebar-settings"].exists)
    }

    /// Garageのサイドバー操作が複数車両カタログへ遷移することを検証します。
    ///
    /// 責務: Garage選択がmacOS専用車両管理画面を描画することを確認します。
    @MainActor
    func testGarageSidebarShowsVehicleCatalog() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        let garageButton = application.buttons["macos-sidebar-garage"]
        XCTAssertTrue(garageButton.waitForExistence(timeout: 5))
        garageButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-garage-screen"].waitForExistence(timeout: 2))
        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "Mac-Garage-Japanese"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// macOSサイドバーの遷移先を操作するとコンテンツ領域が切り替わることを検証します。
    ///
    /// 責務: 1件のサイドバー選択に対応するmacOS遷移先が描画されることを確認します。
    @MainActor
    func testSidebarSelectionShowsMatchingDestination() {
        let application = XCUIApplication.authenticatedProjectZD8()
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
        let application = XCUIApplication.authenticatedProjectZD8()
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
        let application = XCUIApplication.authenticatedProjectZD8()
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
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-settings-screen"].waitForExistence(timeout: 2))
        let primaryAdapterButton = application.buttons["macos-settings-adapter-primary"]
        XCTAssertTrue(primaryAdapterButton.waitForExistence(timeout: 2))
        primaryAdapterButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-primary-adapter-selection"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.radioButtons["USB"].exists)
        XCTAssertTrue(application.radioButtons["Bluetooth"].exists)
    }

    /// USB候補一覧にDEMO USBが常に表示され選択できます。
    ///
    /// 責務: macOSのUSB設定導線が物理接続なしでもデモ候補の詳細確認と確定まで進めることを確認します。
    @MainActor
    func testUSBSelectionAlwaysShowsConfigurableDemoAdapter() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launchArguments += ["-deviceConnection.defaultAdapter", ""]
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()
        let primaryAdapterButton = application.buttons["macos-settings-adapter-primary"]
        XCTAssertTrue(primaryAdapterButton.waitForExistence(timeout: 2))
        primaryAdapterButton.click()

        let demoCandidate = application.buttons["macos-adapter-candidate-usb:projectzd8-demo"]
        XCTAssertTrue(demoCandidate.waitForExistence(timeout: 3))
        demoCandidate.click()
        XCTAssertTrue(application.descendants(matching: .any)["macos-adapter-connection-details"].waitForExistence(timeout: 2))
        let confirmButton = application.buttons["macos-adapter-details-confirm"]
        XCTAssertTrue(confirmButton.exists)
        confirmButton.click()
        XCTAssertFalse(application.descendants(matching: .any)["macos-primary-adapter-selection"].waitForExistence(timeout: 1))
    }

    /// セカンダリーアダプターでも共通の接続方式選択画面へ進めることを検証します。
    ///
    /// 責務: 受信専用セカンダリーがUSBとBluetoothを持つ共通候補モーダルを表示することを確認します。
    @MainActor
    func testSecondaryAdapterSelectionShowsSharedTransportModes() {
        let application = XCUIApplication.authenticatedProjectZD8()
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
        let application = XCUIApplication.authenticatedProjectZD8()
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

    /// 言語と外観の選択が現在のAppShell表示へ反映されシステム追従へ戻ることを検証します。
    ///
    /// 責務: macOS設定画面の言語変更と明示ライトからダークなシステム外観への復帰操作を確認します。
    @MainActor
    func testSettingsAppliesLanguageAndAppearanceToCurrentAppShell() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launchEnvironment["AppleInterfaceStyle"] = "Dark"
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let englishOption = application.radioButtons["English"]
        XCTAssertTrue(englishOption.waitForExistence(timeout: 2))
        englishOption.click()
        XCTAssertEqual(application.buttons["macos-sidebar-home"].label, "Home")

        let lightAppearance = application.buttons["macos-settings-appearance-light"]
        XCTAssertTrue(lightAppearance.exists)
        lightAppearance.click()
        XCTAssertTrue(lightAppearance.isSelected)

        let systemAppearance = application.buttons["macos-settings-appearance-system"]
        systemAppearance.click()
        XCTAssertTrue(systemAppearance.isSelected)
    }

    /// アカウント削除開始操作が最初の警告を表示することを検証します。
    ///
    /// 責務: macOS設定画面の削除開始ボタンが未起動の削除フローへ入力を渡せることを確認します。
    @MainActor
    func testAccountDeletionStartPresentsWarning() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let deleteStart = application.buttons["macos-account-delete-start"]
        if !deleteStart.waitForExistence(timeout: 1) {
            application.descendants(matching: .any)["macos-settings-screen"].swipeUp()
        }
        XCTAssertTrue(deleteStart.waitForExistence(timeout: 2))
        deleteStart.click()

        let nextButton = ["次へ", "Next", "Siguiente"]
            .map { application.sheets.buttons[$0] }
            .first { $0.waitForExistence(timeout: 1) }
        XCTAssertNotNil(nextButton)
    }

    /// アカウント削除が2段階確認後にログイン画面へ戻ることを検証します。
    ///
    /// 責務: macOS設定画面の警告、削除事項、最終削除、ログアウト遷移を一続きで確認します。
    @MainActor
    func testAccountDeletionShowsWarningAndItemsThenReturnsToLogin() {
        let application = XCUIApplication.authenticatedProjectZD8()
        application.launch()

        let settingsButton = application.buttons["macos-sidebar-settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let deleteStart = application.buttons["macos-account-delete-start"]
        if !deleteStart.waitForExistence(timeout: 1) {
            application.descendants(matching: .any)["macos-settings-screen"].swipeUp()
        }
        XCTAssertTrue(deleteStart.waitForExistence(timeout: 2))
        deleteStart.click()

        let nextButton = ["次へ", "Next", "Siguiente"]
            .map { application.sheets.buttons[$0] }
            .first { $0.waitForExistence(timeout: 1) }
        XCTAssertNotNil(nextButton)
        nextButton?.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-account-delete-review"].waitForExistence(timeout: 2))
        let confirmButton = application.buttons["macos-account-delete-confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 2))
        confirmButton.click()

        XCTAssertTrue(application.descendants(matching: .any)["macos-login-screen"].waitForExistence(timeout: 5))
    }
}

/// macOS AppShell UIテスト用の認証済み起動構成を生成します。
private extension XCUIApplication {
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
