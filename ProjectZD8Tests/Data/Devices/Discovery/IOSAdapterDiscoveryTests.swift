#if os(iOS)
import XCTest
@testable import ProjectZD8

/// iOSのExternalAccessoryとBLEの統合、およびアクセサリー候補の変換を検証します。
final class IOSAdapterDiscoveryTests: XCTestCase {
    private let classic = AdapterDescriptor(transport: .bluetoothClassic, systemIdentifier: "external-accessory:abc", displayName: "OBDLink MX+")
    private let ble = AdapterDescriptor(transport: .bluetoothLowEnergy, systemIdentifier: "AAAA", displayName: "OBDLink CX")

    /// 責務: ExternalAccessoryを先に、BLEを重複なく後ろへ統合することを確認します。
    func testMergesClassicThenLowEnergy() async throws {
        let discovery = IOSAdapterDiscovery(
            externalAccessoryDiscovery: DevicesFakeAdapterDiscovery(.success([classic])),
            lowEnergyDiscovery: DevicesFakeAdapterDiscovery(.success([ble, classic]))
        )
        let adapters = try await discovery.discoverAdapters()
        XCTAssertEqual(adapters, [classic, ble])
    }

    /// 責務: Classic候補があればBLE探索の失敗を無視し、無ければ失敗を伝えることを確認します。
    func testLowEnergyFailureOnlyHiddenWhenClassicHasCandidates() async throws {
        let withClassic = IOSAdapterDiscovery(
            externalAccessoryDiscovery: DevicesFakeAdapterDiscovery(.success([classic])),
            lowEnergyDiscovery: DevicesFakeAdapterDiscovery(.failure(.bluetoothPoweredOff))
        )
        let adapters = try await withClassic.discoverAdapters()
        XCTAssertEqual(adapters, [classic])

        let withoutClassic = IOSAdapterDiscovery(
            externalAccessoryDiscovery: DevicesFakeAdapterDiscovery(.success([])),
            lowEnergyDiscovery: DevicesFakeAdapterDiscovery(.failure(.bluetoothPoweredOff))
        )
        do {
            _ = try await withoutClassic.discoverAdapters()
            XCTFail("BLE失敗が握りつぶされた")
        } catch {
            XCTAssertEqual(error as? AdapterDiscoveryError, .bluetoothPoweredOff)
        }
    }

    /// 責務: 接続済みで許可プロトコルを公開するアクセサリーだけが候補になり、シリアル番号が識別子に露出しないことを確認します。
    func testAccessoryMappingFiltersAndProtectsSerialNumber() async throws {
        func snapshot(connected: Bool, protocols: [String]) -> IOSExternalAccessorySnapshot {
            IOSExternalAccessorySnapshot(
                connectionID: 1, name: "OBDLink MX+", manufacturer: "OBD Solutions", modelNumber: "MX+",
                serialNumber: "SN-SECRET", protocolStrings: protocols, isConnected: connected
            )
        }
        let snapshots = [
            snapshot(connected: true, protocols: ["com.obdlink"]),
            snapshot(connected: false, protocols: ["com.obdlink"]),
            snapshot(connected: true, protocols: ["com.other"])
        ]
        let discovery = IOSExternalAccessoryAdapterDiscovery(
            configuration: IOSExternalAccessoryProtocolConfiguration(protocolStrings: [" com.obdlink ", "com.obdlink"]),
            loadSnapshots: { snapshots }
        )
        let adapters = try await discovery.discoverAdapters()
        let adapter = try XCTUnwrap(adapters.first)
        XCTAssertEqual(adapters.count, 1)
        XCTAssertEqual(adapter.transport, .bluetoothClassic)
        XCTAssertEqual(adapter.displayName, "OBDLink MX+")
        XCTAssertEqual(adapter.detail, "OBD Solutions MX+")
        XCTAssertTrue(adapter.systemIdentifier.hasPrefix("external-accessory:"))
        XCTAssertFalse(adapter.systemIdentifier.contains("SN-SECRET"))
    }
}
#endif
