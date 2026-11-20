import XCTest
@testable import ProjectZD8

/// `RouteRecordingSettingsStatus` のケースとローカライズキーを検証します。
final class RouteRecordingSettingsStatusTests: XCTestCase {
    /// 責務: 7 case がそろっていることを確かめます。
    func testHasSevenCases() {
        XCTAssertEqual(RouteRecordingSettingsStatus.allCases.count, 7)
    }

    /// 責務: 各 case のローカライズキーが snake_case の固定値であることを確かめます。
    func testLocalizationKeys() {
        let prefix = "settings.route_recording.status."
        let expected: [(RouteRecordingSettingsStatus, String)] = [
            (.off, "off"),
            (.awaitingPermission, "awaiting_permission"),
            (.recordsInBackground, "records_in_background"),
            (.foregroundOnly, "foreground_only"),
            (.denied, "denied"),
            (.restricted, "restricted"),
            (.unsupportedPlatform, "unsupported_platform")
        ]
        for (status, suffix) in expected {
            XCTAssertEqual(status.localizationKey, prefix + suffix)
        }
    }

    /// 責務: ローカライズキーが case ごとに重複しないことを確かめます。
    func testLocalizationKeysAreUnique() {
        let keys = RouteRecordingSettingsStatus.allCases.map(\.localizationKey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}
