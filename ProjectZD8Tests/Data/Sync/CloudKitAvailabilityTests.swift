import XCTest
@testable import ProjectZD8

/// CloudKitを使ってよい環境の判定を確認します。
final class CloudKitAvailabilityTests: XCTestCase {
    /// 責務: テスト中でなく、エンタイトルメントがある時だけ使えることを確認します。
    func testDecision() {
        XCTAssertTrue(CloudKitAvailability.decide(isRunningTests: false, hasContainerEntitlement: true))
        XCTAssertFalse(CloudKitAvailability.decide(isRunningTests: true, hasContainerEntitlement: true))
        XCTAssertFalse(CloudKitAvailability.decide(isRunningTests: false, hasContainerEntitlement: false))
    }

    /// 責務: テストホストではテスト中と判定され、CloudKitを使わないことを確認します。
    func testTestHostIsDetected() {
        XCTAssertTrue(CloudKitAvailability.isRunningTests())
        XCTAssertFalse(CloudKitAvailability.isCloudKitUsable())
    }
}
