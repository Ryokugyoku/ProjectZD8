#if os(macOS)
import XCTest
@testable import ProjectZD8

/// USBアダプターの表示名決定を検証します。
final class MacOSUSBSerialAdapterDiscoveryTests: XCTestCase {
    /// 責務: メーカー名と製品名を結合し、どちらも無ければ代替識別子を使うことを確認します。
    func testDisplayName() {
        XCTAssertEqual(
            MacOSUSBSerialAdapterDiscovery.displayName(manufacturer: " OBD Solutions ", product: "OBDLink EX", fallback: "/dev/cu.x"),
            "OBD Solutions · OBDLink EX"
        )
        XCTAssertEqual(
            MacOSUSBSerialAdapterDiscovery.displayName(manufacturer: nil, product: "  ", fallback: "/dev/cu.x"),
            "/dev/cu.x"
        )
    }
}
#endif
