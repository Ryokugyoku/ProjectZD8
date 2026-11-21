import XCTest
@testable import ProjectZD8

/// `LocationPermission` の定数を検証します。
final class LocationPermissionTests: XCTestCase {
    /// 責務: `unsupportedPlatform` が専用の段階で、正確な位置ではないことを確かめます。
    func testUnsupportedPlatformPermission() {
        XCTAssertEqual(LocationPermission.unsupportedPlatform.level, .unsupportedPlatform)
        XCTAssertFalse(LocationPermission.unsupportedPlatform.isPreciseAccuracy)
    }
}
