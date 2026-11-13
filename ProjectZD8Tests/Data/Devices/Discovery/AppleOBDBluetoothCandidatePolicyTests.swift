#if os(iOS) || os(macOS)
import XCTest
@testable import ProjectZD8

/// BLE一覧が既知OBD候補だけを公開することを検証します。
final class AppleOBDBluetoothCandidatePolicyTests: XCTestCase {
    private func advertisement(
        localName: String? = nil,
        peripheralName: String? = nil,
        services: [String] = []
    ) -> BluetoothAdvertisement {
        BluetoothAdvertisement(
            peripheralIdentifier: UUID(),
            localName: localName,
            peripheralName: peripheralName,
            serviceIdentifiers: services
        )
    }

    /// 責務: OBDLink、VEEPEAK、Vgate、IOS-Vlinkの名称接頭辞(大文字小文字無視)を許可することを確認します。
    func testAcceptsKnownProductNames() {
        let policy = AppleOBDBluetoothCandidatePolicy()
        for name in ["OBDLink CX", "obdlink mx+", "VEEPEAK", "Vgate iCar Pro", "IOS-Vlink", " OBDLink EX"] {
            XCTAssertTrue(policy.accepts(advertisement(localName: name)), name)
            XCTAssertTrue(policy.accepts(advertisement(peripheralName: name)), name)
        }
    }

    /// 責務: 名称が不明でも、既知UART Service UUIDを広告する機器を許可することを確認します。
    func testAcceptsKnownUARTServices() {
        let policy = AppleOBDBluetoothCandidatePolicy()
        for service in AppleBluetoothUARTProfile.supported.map(\.serviceUUID) {
            XCTAssertTrue(policy.accepts(advertisement(services: [service.lowercased()])), service)
        }
    }

    /// 責務: 一般のBLE機器やUUIDだけの機器を除外することを確認します。
    func testRejectsUnrelatedPeripherals() {
        let policy = AppleOBDBluetoothCandidatePolicy()
        XCTAssertFalse(policy.accepts(advertisement()))
        XCTAssertFalse(policy.accepts(advertisement(localName: "Galaxy Watch", services: ["180F"])))
        XCTAssertFalse(policy.accepts(advertisement(peripheralName: "My OBDLink")))
    }
}
#endif
