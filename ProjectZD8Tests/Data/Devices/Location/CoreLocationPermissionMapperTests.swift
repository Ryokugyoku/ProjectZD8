import CoreLocation
import Foundation
import XCTest
@testable import ProjectZD8

/// `CoreLocationPermissionMapper` の許可段階と精度の対応を検証します。
final class CoreLocationPermissionMapperTests: XCTestCase {
    /// `authorizedWhenInUse` は macOS の SDK では使えないため、同じ値(4)から作ります。
    private func whenInUseStatus() throws -> CLAuthorizationStatus {
        try XCTUnwrap(CLAuthorizationStatus(rawValue: 4), "rawValue 4 は authorizedWhenInUse")
    }

    /// 検証する (状態, 期待する許可段階) の一覧です。
    ///
    /// 責務: macOS でも使える case と、値から作った whenInUse を合わせて返します。
    private func expectedLevels() throws -> [(CLAuthorizationStatus, LocationAuthorizationLevel)] {
        [
            (.notDetermined, .notDetermined), (.denied, .denied), (.restricted, .restricted),
            (try whenInUseStatus(), .whenInUse), (.authorizedAlways, .always)
        ]
    }

    /// 各状態が対応する許可段階になります。
    ///
    /// 責務: 全状態を、両方の精度設定で確認します。
    func testEachStatusMapsToItsLevel() throws {
        let mapper = CoreLocationPermissionMapper()
        for (status, level) in try expectedLevels() {
            for accuracy in [CLAccuracyAuthorization.fullAccuracy, .reducedAccuracy] {
                XCTAssertEqual(mapper.permission(status: status, accuracy: accuracy).level, level, "\(status.rawValue)")
            }
        }
    }

    /// 精度は fullAccuracy の時だけ true です。
    ///
    /// 責務: 全状態との組み合わせで isPreciseAccuracy を確認します。
    func testPreciseAccuracyFollowsAccuracyAuthorization() throws {
        let mapper = CoreLocationPermissionMapper()
        for (status, _) in try expectedLevels() {
            XCTAssertTrue(mapper.permission(status: status, accuracy: .fullAccuracy).isPreciseAccuracy, "\(status.rawValue)")
            XCTAssertFalse(mapper.permission(status: status, accuracy: .reducedAccuracy).isPreciseAccuracy, "\(status.rawValue)")
        }
    }
}
