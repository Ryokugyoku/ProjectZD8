import Foundation
import XCTest
@testable import ProjectZD8

/// `UnavailableLocationAuthorization` が常に非対応を返し、要求を無視することを検証します。
@MainActor
final class UnavailableLocationAuthorizationTests: XCTestCase {
    /// 現在の許可は非対応のプラットフォームです。
    ///
    /// 責務: `currentPermission` が `unsupportedPlatform` であることを確認します。
    func testCurrentPermissionIsUnsupportedPlatform() {
        XCTAssertEqual(UnavailableLocationAuthorization().currentPermission, LocationPermission.unsupportedPlatform)
    }

    /// 許可の変化の流れは何も流さずに終わります。
    ///
    /// 責務: 流れが2秒以内に空のまま終わることを確認します。終わらなければ失敗します。
    func testPermissionChangesFinishWithoutEmitting() async {
        let stream = UnavailableLocationAuthorization().permissionChanges()
        let result = await withTaskGroup(of: (values: [LocationPermission], finished: Bool).self) { group in
            group.addTask {
                var values: [LocationPermission] = []
                for await value in stream { values.append(value) }
                return (values, true)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return ([], false)
            }
            let first = await group.next() ?? ([], false)
            group.cancelAll()
            return first
        }

        XCTAssertTrue(result.finished, "流れが2秒以内に終わらなかった")
        XCTAssertTrue(result.values.isEmpty)
    }

    /// 2つの許可要求を呼んでも現在の許可は変わりません。
    ///
    /// 責務: 要求メソッドの呼び出し前後で `currentPermission` が同じことを確認します。
    func testRequestsDoNotChangeCurrentPermission() {
        let authorization = UnavailableLocationAuthorization()

        authorization.requestWhenInUseAuthorization()
        XCTAssertEqual(authorization.currentPermission, LocationPermission.unsupportedPlatform)
        authorization.requestAlwaysAuthorization()
        XCTAssertEqual(authorization.currentPermission, LocationPermission.unsupportedPlatform)
    }
}
