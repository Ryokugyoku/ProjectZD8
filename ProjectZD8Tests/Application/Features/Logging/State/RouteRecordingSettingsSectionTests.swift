import XCTest
@testable import ProjectZD8

/// `RouteRecordingSettingsSection` の状態・注意表示・警告・リンク・固定キーを検証します。
final class RouteRecordingSettingsSectionTests: XCTestCase {
    /// 責務: 許可の段階と精度から区画を作ります。
    private func section(
        _ isEnabled: Bool,
        _ level: LocationAuthorizationLevel,
        precise: Bool = true
    ) -> RouteRecordingSettingsSection {
        RouteRecordingSettingsSection(
            isEnabled: isEnabled,
            permission: LocationPermission(level: level, isPreciseAccuracy: precise)
        )
    }

    /// 責務: 設定オンの時の状態が許可の段階ごとに決まることを確かめます。
    func testStatusWhenEnabled() {
        let expected: [(LocationAuthorizationLevel, RouteRecordingSettingsStatus)] = [
            (.notDetermined, .awaitingPermission),
            (.denied, .denied),
            (.restricted, .restricted),
            (.whenInUse, .foregroundOnly),
            (.always, .recordsInBackground),
            (.unsupportedPlatform, .unsupportedPlatform)
        ]
        for (level, status) in expected {
            XCTAssertEqual(section(true, level).status, status, "\(level)")
        }
    }

    /// 責務: 設定オフなら非対応を除き、どの許可でも off になることを確かめます。
    func testStatusWhenDisabled() {
        for level in LocationAuthorizationLevel.allCases where level != .unsupportedPlatform {
            XCTAssertEqual(section(false, level).status, .off, "\(level)")
        }
        XCTAssertEqual(section(false, .unsupportedPlatform).status, .unsupportedPlatform)
    }

    /// 責務: isEnabled が引数どおりに保持されることを確かめます。
    func testIsEnabledIsKept() {
        XCTAssertTrue(section(true, .always).isEnabled)
        XCTAssertFalse(section(false, .always).isEnabled)
    }

    /// 責務: 概略の位置の注意が、オンかつ許可ありかつ概略の時だけ出ることを確かめます。
    func testShowsReducedAccuracyNoticeOnlyWhenEnabledAuthorizedAndReduced() {
        for level in LocationAuthorizationLevel.allCases {
            let authorized = level == .whenInUse || level == .always
            XCTAssertEqual(section(true, level, precise: false).showsReducedAccuracyNotice, authorized, "\(level)")
            XCTAssertFalse(section(true, level, precise: true).showsReducedAccuracyNotice, "\(level)")
            XCTAssertFalse(section(false, level, precise: false).showsReducedAccuracyNotice, "\(level)")
        }
    }

    /// 責務: 警告表示が denied・restricted・foregroundOnly・概略の注意の時だけ true になることを確かめます。
    func testIsWarning() {
        XCTAssertTrue(section(true, .denied).isWarning)
        XCTAssertTrue(section(true, .restricted).isWarning)
        XCTAssertTrue(section(true, .whenInUse).isWarning)
        XCTAssertTrue(section(true, .always, precise: false).isWarning)
        XCTAssertFalse(section(false, .denied).isWarning)
        XCTAssertFalse(section(true, .notDetermined).isWarning)
        XCTAssertFalse(section(true, .always, precise: true).isWarning)
        XCTAssertFalse(section(true, .unsupportedPlatform).isWarning)
        XCTAssertFalse(section(false, .always, precise: false).isWarning)
    }

    /// 責務: 設定アプリへのリンクが denied・foregroundOnly・概略の注意の時だけ出ることを確かめます。
    func testShowsSystemSettingsLink() {
        XCTAssertTrue(section(true, .denied).showsSystemSettingsLink)
        XCTAssertTrue(section(true, .whenInUse).showsSystemSettingsLink)
        XCTAssertTrue(section(true, .always, precise: false).showsSystemSettingsLink)
        XCTAssertFalse(section(true, .restricted).showsSystemSettingsLink)
        XCTAssertFalse(section(true, .notDetermined).showsSystemSettingsLink)
        XCTAssertFalse(section(true, .always, precise: true).showsSystemSettingsLink)
        XCTAssertFalse(section(false, .denied).showsSystemSettingsLink)
        XCTAssertFalse(section(true, .unsupportedPlatform).showsSystemSettingsLink)
    }

    /// 責務: 固定のローカライズキーが仕様どおりであることを確かめます。
    func testStaticKeys() {
        XCTAssertEqual(RouteRecordingSettingsSection.eyebrowKey, "settings.route_recording.eyebrow")
        XCTAssertEqual(RouteRecordingSettingsSection.titleKey, "settings.route_recording.title")
        XCTAssertEqual(RouteRecordingSettingsSection.descriptionKey, "settings.route_recording.description")
        XCTAssertEqual(RouteRecordingSettingsSection.toggleKey, "settings.route_recording.toggle")
        XCTAssertEqual(
            RouteRecordingSettingsSection.reducedAccuracyNoticeKey,
            "settings.route_recording.reduced_accuracy_notice"
        )
        XCTAssertEqual(
            RouteRecordingSettingsSection.openSystemSettingsKey,
            "settings.route_recording.open_system_settings"
        )
    }
}
