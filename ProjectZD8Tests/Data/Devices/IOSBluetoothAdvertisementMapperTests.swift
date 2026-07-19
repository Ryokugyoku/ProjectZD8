#if os(iOS)
import XCTest
@testable import ProjectZD8

/// iOSのBluetoothアドバタイズメント変換規則を検証します。
@MainActor
final class IOSBluetoothAdvertisementMapperTests: XCTestCase {
    /// Advertisement Local Nameが周辺機器名より優先されることを検証します。
    ///
    /// 責務: BLE候補の表示名が指定された名称優先順位に従うことを確認します。
    func testAdvertisementLocalNameTakesPriorityOverPeripheralName() {
        let adapter = IOSBluetoothAdvertisementMapper().makeAdapter(
            peripheralIdentifier: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            advertisementLocalName: "Advertisement Name",
            peripheralName: "Peripheral Name",
            connectionState: .disconnected,
            hasManufacturerData: true
        )

        XCTAssertEqual(adapter.displayName, "Advertisement Name")
        XCTAssertEqual(adapter.advertisementLocalName, "Advertisement Name")
        XCTAssertEqual(adapter.productName, "Peripheral Name")
        XCTAssertEqual(adapter.hasManufacturerData, true)
        XCTAssertNil(adapter.manufacturerName)
    }

    /// 名称を取得できない場合にPeripheral UUIDを表示名へ使うことを検証します。
    ///
    /// 責務: 空または取得不能のBLE名称が完全なPeripheral UUIDへフォールバックすることを確認します。
    func testMissingNamesFallBackToPeripheralUUID() {
        let identifier = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let adapter = IOSBluetoothAdvertisementMapper().makeAdapter(
            peripheralIdentifier: identifier,
            advertisementLocalName: "   ",
            peripheralName: nil,
            connectionState: .disconnected,
            hasManufacturerData: false
        )

        XCTAssertEqual(adapter.displayName, identifier.uuidString)
        XCTAssertEqual(adapter.systemIdentifier, identifier.uuidString)
        XCTAssertNil(adapter.advertisementLocalName)
    }
}
#endif
