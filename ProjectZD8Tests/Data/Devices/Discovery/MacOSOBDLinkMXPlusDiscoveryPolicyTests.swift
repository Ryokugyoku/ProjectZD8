#if os(macOS)
import XCTest
@testable import ProjectZD8

/// OBDLink MX+候補を名称とペアリング状態で限定する方針を検証します。
final class MacOSOBDLinkMXPlusDiscoveryPolicyTests: XCTestCase {
    /// 責務: ペアリング済みの公式名称と、機器固有の接尾辞つき名称を受け入れることを確認します。
    func testAcceptsPairedOfficialNames() {
        let policy = MacOSOBDLinkMXPlusDiscoveryPolicy()
        XCTAssertTrue(policy.accepts(name: "OBDLink MX+", isPaired: true))
        XCTAssertTrue(policy.accepts(name: "OBDLink MX+ 48318", isPaired: true))
    }

    /// 責務: 未ペアリングのMX+を受け入れないことを確認します。
    func testRejectsUnpaired() {
        XCTAssertFalse(MacOSOBDLinkMXPlusDiscoveryPolicy().accepts(name: "OBDLink MX+", isPaired: false))
    }

    /// 責務: 他モデルや名称の似た機器をMX+と誤認しないことを確認します。
    func testRejectsOtherProducts() {
        let policy = MacOSOBDLinkMXPlusDiscoveryPolicy()
        XCTAssertFalse(policy.accepts(name: "OBDLink CX", isPaired: true))
        XCTAssertFalse(policy.accepts(name: "OBDLink MX", isPaired: true))
        XCTAssertFalse(policy.accepts(name: "OBDLink MX+Clone", isPaired: true))
    }
}
#endif
