#if os(macOS)
import XCTest
@testable import ProjectZD8

/// macOS探索が既存USBとBluetooth Classicを維持しながら共通BLEを統合することを検証します。
@MainActor
final class MacOSAdapterDiscoveryTests: XCTestCase {
    /// USB要求が既存macOSシステム探索だけへ渡されることを検証します。
    ///
    /// 責務: USB探索経路がBLE探索追加後も変更されないことを確認します。
    func testUSBUsesOnlyExistingSystemDiscovery() async throws {
        let usb = makeAdapter(id: "usb:/dev/cu.test", transport: .serial)
        let systemDiscovery = MacOSAdapterDiscoveryStub(result: .success([usb]))
        let lowEnergyDiscovery = MacOSAdapterDiscoveryStub(result: .success([]))
        let discovery = MacOSAdapterDiscovery(
            systemDiscovery: systemDiscovery,
            lowEnergyDiscovery: lowEnergyDiscovery
        )

        let adapters = try await discovery.discoverAdapters(for: .usb)

        XCTAssertEqual(adapters, [usb])
        XCTAssertEqual(systemDiscovery.requestedModes, [.usb])
        XCTAssertTrue(lowEnergyDiscovery.requestedModes.isEmpty)
    }

    /// Bluetooth要求がClassicとBLEの候補を同じ一覧へ統合することを検証します。
    ///
    /// 責務: 2種類のmacOS Bluetooth探索結果が欠落なく返ることを確認します。
    func testBluetoothMergesClassicAndLowEnergyCandidates() async throws {
        let classic = makeAdapter(id: "bluetooth-classic:AA-BB", transport: .bluetoothClassic)
        let lowEnergy = makeAdapter(id: "bluetooth-low-energy:UUID", transport: .bluetoothLowEnergy)
        let discovery = MacOSAdapterDiscovery(
            systemDiscovery: MacOSAdapterDiscoveryStub(result: .success([classic])),
            lowEnergyDiscovery: MacOSAdapterDiscoveryStub(result: .success([lowEnergy]))
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertEqual(adapters, [classic, lowEnergy])
    }

    /// Bluetooth方式の一方が失敗しても他方の候補を返すことを検証します。
    ///
    /// 責務: BLE探索の成功をBluetooth Classic探索の失敗から独立して保持することを確認します。
    func testBluetoothKeepsLowEnergyCandidatesWhenClassicFails() async throws {
        let lowEnergy = makeAdapter(id: "bluetooth-low-energy:UUID", transport: .bluetoothLowEnergy)
        let discovery = MacOSAdapterDiscovery(
            systemDiscovery: MacOSAdapterDiscoveryStub(result: .failure(.bluetoothStateUnavailable)),
            lowEnergyDiscovery: MacOSAdapterDiscoveryStub(result: .success([lowEnergy]))
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertEqual(adapters, [lowEnergy])
    }

    /// Bluetooth方式が両方とも失敗した場合に利用不能を返すことを検証します。
    ///
    /// 責務: 候補取得不能を空の正常結果へ変換しないことを確認します。
    func testBluetoothFailsWhenBothDiscoveriesFail() async {
        let discovery = MacOSAdapterDiscovery(
            systemDiscovery: MacOSAdapterDiscoveryStub(result: .failure(.bluetoothStateUnavailable)),
            lowEnergyDiscovery: MacOSAdapterDiscoveryStub(result: .failure(.bluetoothPoweredOff))
        )

        do {
            _ = try await discovery.discoverAdapters(for: .bluetooth)
            XCTFail("Expected discovery to fail")
        } catch {
            XCTAssertEqual(error as? AdapterDiscoveryError, .bluetoothStateUnavailable)
        }
    }

    /// テスト用の接続方式を持つ候補を生成します。
    ///
    /// 責務: 1件の探索候補を指定された安定識別子と物理方式で構築します。
    /// - Parameters:
    ///   - id: 候補の安定識別子。
    ///   - transport: OBD通信に使用する物理方式。
    /// - Returns: 接続済みとして扱うBluetoothまたはUSB候補。
    private func makeAdapter(
        id: String,
        transport: OBDConnectionEndpoint.Transport
    ) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: transport == .serial ? .usb : .bluetooth,
            connectionTransport: transport,
            displayName: id,
            systemIdentifier: id,
            isConnected: true
        )
    }
}

/// macOS探索の要求履歴と決定済み結果を保持するテスト代替です。
@MainActor
private final class MacOSAdapterDiscoveryStub: AdapterDiscoveryPort {
    /// 各探索要求へ返す決定済み結果です。
    private let result: Result<[DiscoveredAdapter], AdapterDiscoveryError>

    /// 受け取った接続方式を呼出順で保持します。
    private(set) var requestedModes: [AdapterTransportMode] = []

    /// 決定済み探索結果を注入して生成します。
    ///
    /// 責務: 1件のテスト用探索結果を後続要求へ返せる状態で保持します。
    /// - Parameter result: 探索要求時に返す成功候補またはエラー。
    init(result: Result<[DiscoveredAdapter], AdapterDiscoveryError>) {
        self.result = result
    }

    /// 探索方式を記録して決定済み結果を返します。
    ///
    /// 責務: 1回の探索要求を履歴へ追加して注入済み結果を再現します。
    /// - Parameter mode: 要求された物理接続方式。
    /// - Returns: 注入済みの探索候補。
    /// - Throws: 注入済み結果が失敗の場合の探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        requestedModes.append(mode)
        return try result.get()
    }
}
#endif
