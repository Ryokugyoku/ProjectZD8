#if os(macOS)
import XCTest
@testable import ProjectZD8

/// macOSのOBDLink MX+探索候補を名称とペアリング状態で保守的に限定できることを検証します。
final class MacOSOBDLinkMXPlusDiscoveryPolicyTests: XCTestCase {
    /// ペアリング済みの公式名称をMX+候補として受け入れます。
    ///
    /// 責務: 基本のMX+名称がペアリング完了後だけ候補になることを確認します。
    func testAcceptsPairedOfficialName() {
        let policy = MacOSOBDLinkMXPlusDiscoveryPolicy()

        XCTAssertTrue(policy.accepts(name: "OBDLink MX+", isPaired: true))
    }

    /// 製品名の後ろに機器固有接尾辞がある名称も受け入れます。
    ///
    /// 責務: MX+名称接頭辞と機器固有接尾辞を持つペアリング済み候補を確認します。
    func testAcceptsPairedNameWithDeviceSuffix() {
        let policy = MacOSOBDLinkMXPlusDiscoveryPolicy()

        XCTAssertTrue(policy.accepts(name: "OBDLink MX+ 48318", isPaired: true))
    }

    /// 正しい名称でも未ペアリングなら候補へ追加しません。
    ///
    /// 責務: macOS接続前提を満たさないMX+を選択可能状態へ進めないことを確認します。
    func testRejectsUnpairedMXPlus() {
        let policy = MacOSOBDLinkMXPlusDiscoveryPolicy()

        XCTAssertFalse(policy.accepts(name: "OBDLink MX+", isPaired: false))
    }

    /// ペアリング済みでも他製品はMX+候補へ追加しません。
    ///
    /// 責務: OBDLinkの別モデルや名称の似た機器をMX+と誤認しないことを確認します。
    func testRejectsOtherBluetoothProducts() {
        let policy = MacOSOBDLinkMXPlusDiscoveryPolicy()

        XCTAssertFalse(policy.accepts(name: "OBDLink CX", isPaired: true))
        XCTAssertFalse(policy.accepts(name: "OBDLink MX", isPaired: true))
        XCTAssertFalse(policy.accepts(name: "OBDLink MX+Clone", isPaired: true))
    }
}
#endif
