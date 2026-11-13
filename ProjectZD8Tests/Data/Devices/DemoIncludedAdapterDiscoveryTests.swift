import XCTest
@testable import ProjectZD8

/// 実探索結果へ接続方式別にデモ候補が追加されることを検証します。
@MainActor
final class DemoIncludedAdapterDiscoveryTests: XCTestCase {
    /// 空のUSB探索にもDEMO USBを3件返します。
    ///
    /// 責務: USB探索結果が常にデモ候補を含むことを確認します。
    func testUSBDiscoveryAlwaysIncludesDemoCandidate() async throws {
        let discovery = DemoIncludedAdapterDiscovery(
            wrapping: EmptyAdapterDiscovery(),
            demoCandidates: DemoOBDAdapter.usbCandidates
        )

        let adapters = try await discovery.discoverAdapters(for: .usb)

        XCTAssertEqual(adapters, DemoOBDAdapter.usbCandidates)
    }

    /// Bluetooth探索にはUSBデモ候補を混在させません。
    ///
    /// 責務: Bluetooth探索結果がデモUSB候補を含まないことを確認します。
    func testBluetoothDiscoveryDoesNotIncludeDemoUSB() async throws {
        let discovery = DemoIncludedAdapterDiscovery(
            wrapping: EmptyAdapterDiscovery(),
            demoCandidates: DemoOBDAdapter.usbCandidates
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertTrue(adapters.isEmpty)
    }

    /// Bluetoothデモ候補3件をBluetooth探索へ追加します。
    ///
    /// 責務: Bluetooth向け構成がiOS用デモ候補を返すことを確認します。
    func testBluetoothDiscoveryIncludesBluetoothDemoCandidate() async throws {
        let discovery = DemoIncludedAdapterDiscovery(
            wrapping: EmptyAdapterDiscovery(),
            demoCandidates: DemoOBDAdapter.bluetoothCandidates
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertEqual(adapters, DemoOBDAdapter.bluetoothCandidates)
    }

    /// 実Bluetooth探索が利用不能でもデモ候補3件は残します。
    ///
    /// 責務: Bluetooth利用不可をデモ候補まで消す失敗へ変換しないことを確認します。
    func testBluetoothFailureStillReturnsBluetoothDemoCandidate() async throws {
        let discovery = DemoIncludedAdapterDiscovery(
            wrapping: FailingBluetoothAdapterDiscovery(),
            demoCandidates: DemoOBDAdapter.bluetoothCandidates
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertEqual(adapters, DemoOBDAdapter.bluetoothCandidates)
    }
}

/// Bluetooth利用不能を返すテスト用探索境界です。
@MainActor
private struct FailingBluetoothAdapterDiscovery: AdapterDiscoveryPort {
    /// 利用不能な探索境界を生成します。
    ///
    /// 責務: Bluetooth探索失敗を再現する境界を構築します。
    init() {}

    /// Bluetooth利用不能エラーを返します。
    ///
    /// 責務: 1回の探索要求をBluetooth利用不能結果へ変換します。
    /// - Parameter mode: テストでは使用しない接続方式。
    /// - Returns: この実装は候補を返しません。
    /// - Throws: 常に `AdapterDiscoveryError.bluetoothPoweredOff`。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        throw AdapterDiscoveryError.bluetoothPoweredOff
    }
}

/// 候補を返さないテスト用探索境界です。
@MainActor
private struct EmptyAdapterDiscovery: AdapterDiscoveryPort {
    /// 空の探索境界を生成します。
    ///
    /// 責務: 候補を持たない探索状態を構築します。
    init() {}

    /// 任意の接続方式へ空の候補一覧を返します。
    ///
    /// 責務: 1回の探索要求を空結果へ変換します。
    /// - Parameter mode: テストでは使用しない接続方式。
    /// - Returns: 常に空の候補一覧。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] { [] }
}
