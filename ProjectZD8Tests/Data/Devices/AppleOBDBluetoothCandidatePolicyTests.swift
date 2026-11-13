#if os(iOS) || os(macOS)
import XCTest
@testable import ProjectZD8

/// AppleプラットフォームのBLE一覧が既知OBD候補だけを公開することを検証します。
final class AppleOBDBluetoothCandidatePolicyTests: XCTestCase {
    /// 公式に確認したOBDLink、VEEPEAK、VgateのBLE名称を許可することを検証します。
    ///
    /// 責務: 既知OBDメーカーの広告名称が選択候補として保持されることを確認します。
    func testAcceptsKnownOBDProductNames() {
        let policy = AppleOBDBluetoothCandidatePolicy()

        XCTAssertTrue(policy.accepts(makeAdapter(name: "OBDLink CX")))
        XCTAssertTrue(policy.accepts(makeAdapter(name: "VEEPEAK")))
        XCTAssertTrue(policy.accepts(makeAdapter(name: "Vgate iCar Pro")))
        XCTAssertTrue(policy.accepts(makeAdapter(name: "IOS-Vlink")))
    }

    /// 名称が不明でも既知UART Service UUIDを持つ候補を許可することを検証します。
    ///
    /// 責務: 採用済みUART構成を広告するBLE候補が名称欠損だけで除外されないことを確認します。
    func testAcceptsKnownUARTServiceIdentifiers() {
        let policy = AppleOBDBluetoothCandidatePolicy()

        for serviceIdentifier in AppleBluetoothUARTProfile.supported.map(\.serviceUUID) {
            XCTAssertTrue(
                policy.accepts(
                    makeAdapter(
                        name: UUID().uuidString,
                        serviceIdentifiers: [serviceIdentifier]
                    )
                ),
                serviceIdentifier
            )
        }
    }

    /// OBD信号を持たない周辺BLE機器を除外することを検証します。
    ///
    /// 責務: 一般アクセサリー、UUID表示、Manufacturer Dataだけの候補をOBD一覧へ混入させないことを確認します。
    func testRejectsUnrelatedBluetoothPeripherals() {
        let policy = AppleOBDBluetoothCandidatePolicy()

        XCTAssertFalse(policy.accepts(makeAdapter(name: "AirPods Pro")))
        XCTAssertFalse(policy.accepts(makeAdapter(name: "Pioneer Navi")))
        XCTAssertFalse(
            policy.accepts(
                makeAdapter(
                    name: "11111111-2222-3333-4444-555555555555",
                    hasManufacturerData: true
                )
            )
        )
    }

    /// 判定テスト用のBLE候補を生成します。
    ///
    /// 責務: 表示名と広告信号だけを変更可能なBLE候補を一意に構築します。
    /// - Parameters:
    ///   - name: 広告および一覧へ表示する名称。
    ///   - serviceIdentifiers: 広告に含めるService UUID一覧。
    ///   - hasManufacturerData: Manufacturer Dataを持つかどうか。
    /// - Returns: 未接続のCoreBluetooth候補。
    private func makeAdapter(
        name: String,
        serviceIdentifiers: [String] = [],
        hasManufacturerData: Bool = false
    ) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: "bluetooth-low-energy:\(name)",
            transportMode: .bluetooth,
            displayName: name,
            productName: name,
            advertisementLocalName: name,
            hasManufacturerData: hasManufacturerData,
            bluetoothServiceIdentifiers: serviceIdentifiers,
            systemIdentifier: name,
            isConnected: false
        )
    }
}
#endif
