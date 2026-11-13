import XCTest
@testable import ProjectZD8

/// BLE検出値からアダプター記述への変換を検証します。
final class AppleBluetoothAdvertisementMapperTests: XCTestCase {
    /// 責務: ローカル名を最優先の表示名にし、異なる周辺機器名を詳細へ残すことを確認します。
    func testPrefersLocalNameAndKeepsSystemNameAsDetail() {
        let id = UUID()
        let adapter = AppleBluetoothAdvertisementMapper().makeAdapter(from: BluetoothAdvertisement(
            peripheralIdentifier: id, localName: " OBDLink CX ", peripheralName: "CX-1234"
        ))
        XCTAssertEqual(adapter.transport, .bluetoothLowEnergy)
        XCTAssertEqual(adapter.systemIdentifier, id.uuidString)
        XCTAssertEqual(adapter.displayName, "OBDLink CX")
        XCTAssertEqual(adapter.detail, "CX-1234")
    }

    /// 責務: 名称が空白だけならUUIDを表示名にすることを確認します。
    func testFallsBackToIdentifier() {
        let id = UUID()
        let adapter = AppleBluetoothAdvertisementMapper().makeAdapter(from: BluetoothAdvertisement(
            peripheralIdentifier: id, localName: "  ", peripheralName: nil
        ))
        XCTAssertEqual(adapter.displayName, id.uuidString)
        XCTAssertNil(adapter.detail)
    }
}
