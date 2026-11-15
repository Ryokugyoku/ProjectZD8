import UserNotifications
import XCTest
@testable import ProjectZD8

/// `VehicleDetectionNotificationAuthorizationPolicy` が通知の許可状態ごとに監視通知の提示可否を決めることを検証します。
final class VehicleDetectionNotificationAuthorizationPolicyTests: XCTestCase {
    /// 検証対象の方針です。
    private let policy = VehicleDetectionNotificationAuthorizationPolicy()

    /// 許可済み・仮許可・一時許可(iOS のみの状態)では提示します。
    ///
    /// 責務: 提示可能な許可状態で `true` になることを確認します。
    func testAuthorizedStatesAllowPresentation() {
        var statuses: [UNAuthorizationStatus] = [.authorized, .provisional]
        #if os(iOS)
        statuses.append(.ephemeral)
        #endif
        for status in statuses {
            XCTAssertTrue(policy.allowsPresentation(status), "\(status.rawValue)")
        }
    }

    /// 拒否・未決定(許可なし)では提示しません。
    ///
    /// 責務: 許可の無い状態で `false` になることを確認します。
    func testUnauthorizedStatesDoNotAllowPresentation() {
        for status in [UNAuthorizationStatus.denied, .notDetermined] {
            XCTAssertFalse(policy.allowsPresentation(status), "\(status.rawValue)")
        }
    }

    /// 未知の許可状態でも提示しません。
    ///
    /// 責務: 将来追加される状態(既知の値に無い raw 値)で `false` になることを確認します。
    func testUnknownStatusDoesNotAllowPresentation() throws {
        let unknown = try XCTUnwrap(UNAuthorizationStatus(rawValue: 99))
        XCTAssertFalse(policy.allowsPresentation(unknown))
    }
}
