#if os(macOS)
import XCTest
@testable import ProjectZD8

/// macOSの3方式の探索結果の統合を検証します。
final class MacOSAdapterDiscoveryTests: XCTestCase {
    private let usb = AdapterDescriptor(transport: .usbSerial, systemIdentifier: "/dev/cu.usbserial-1", displayName: "OBDLink EX")
    private let classic = AdapterDescriptor(transport: .bluetoothClassic, systemIdentifier: "00-11", displayName: "OBDLink MX+")
    private let ble = AdapterDescriptor(transport: .bluetoothLowEnergy, systemIdentifier: "AAAA", displayName: "OBDLink CX")

    private func discovery(
        usb: Result<[AdapterDescriptor], AdapterDiscoveryError>,
        classic: Result<[AdapterDescriptor], AdapterDiscoveryError>,
        ble: Result<[AdapterDescriptor], AdapterDiscoveryError>
    ) -> MacOSAdapterDiscovery {
        MacOSAdapterDiscovery(
            usbDiscovery: DevicesFakeAdapterDiscovery(usb),
            classicDiscovery: DevicesFakeAdapterDiscovery(classic),
            lowEnergyDiscovery: DevicesFakeAdapterDiscovery(ble)
        )
    }

    /// 責務: 3方式の候補を重複なく統合し、デモアダプターを含めないことを確認します。
    func testMergesAllSourcesWithoutDuplicates() async throws {
        let adapters = try await discovery(
            usb: .success([usb]), classic: .success([classic]), ble: .success([ble, classic])
        ).discoverAdapters()
        XCTAssertEqual(adapters, [usb, classic, ble])
        XCTAssertFalse(adapters.contains { $0.transport == .demo })
    }

    /// 責務: 一部の方式が失敗しても、成功した方式の候補を返すことを確認します。
    func testReturnsSucceededSourcesWhenOthersFail() async throws {
        let adapters = try await discovery(
            usb: .success([usb]), classic: .failure(.failed), ble: .failure(.bluetoothPoweredOff)
        ).discoverAdapters()
        XCTAssertEqual(adapters, [usb])
    }

    /// 責務: 全方式が失敗した場合、BLEの具体的な失敗を優先して投げることを確認します。
    func testThrowsMostSpecificFailureWhenAllFail() async {
        do {
            _ = try await discovery(
                usb: .failure(.failed), classic: .failure(.failed), ble: .failure(.bluetoothUnauthorized)
            ).discoverAdapters()
            XCTFail("全失敗が成功扱いになった")
        } catch {
            XCTAssertEqual(error as? AdapterDiscoveryError, .bluetoothUnauthorized)
        }
    }

    /// 責務: 全方式が空でも失敗ではなく空の結果を返すことを確認します。
    func testEmptySuccessIsNotAFailure() async throws {
        let adapters = try await discovery(usb: .success([]), classic: .success([]), ble: .success([])).discoverAdapters()
        XCTAssertEqual(adapters, [])
    }
}
#endif
