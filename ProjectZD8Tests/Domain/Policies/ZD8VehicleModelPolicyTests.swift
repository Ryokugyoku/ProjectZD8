import XCTest
@testable import ProjectZD8

/// ZD8型式の国内識別子と海外VIN照合を検証します。
final class ZD8VehicleModelPolicyTests: XCTestCase {
    /// 国内型式接頭辞とJF1ZD VINだけを受理します。
    ///
    /// 責務: ZD8専用PIDが他車種へ適用されない識別境界を確認します。
    func testMatchesOnlyZD8Identifiers() {
        let policy = ZD8VehicleModelPolicy()

        XCTAssertTrue(policy.matches("ZD8-012345"))
        XCTAssertTrue(policy.matches("JF1ZD8ABCDEF12345"))
        XCTAssertFalse(policy.matches("ZN8-012345"))
        XCTAssertFalse(policy.matches("JF1ZC6ABCDEF12345"))
        XCTAssertFalse(policy.matches(nil))
    }
}
