#if os(iOS)
import XCTest
@testable import ProjectZD8

/// iOS ExternalAccessoryの構成、候補判定、識別値保護を検証します。
@MainActor
final class IOSExternalAccessoryAdapterDiscoveryTests: XCTestCase {
    /// プロトコル構成が空白と重複を除くことを検証します。
    ///
    /// 責務: Info.plist相当の入力が比較可能な許可集合へ正規化されることを確認します。
    func testProtocolConfigurationNormalizesValues() {
        let configuration = IOSExternalAccessoryProtocolConfiguration(
            protocolStrings: [" com.example.obd ", "com.example.obd", "   "]
        )

        XCTAssertEqual(configuration.protocolStrings, ["com.example.obd"])
        XCTAssertEqual(
            configuration.matchingProtocol(in: ["unrelated", "com.example.obd"]),
            "com.example.obd"
        )
    }

    /// 許可済みプロトコルを持つ接続済みMX+候補がClassic終端になることを検証します。
    ///
    /// 責務: 接続済みExternalAccessory検出値が選択可能なBluetooth Classic候補へ変換されることを確認します。
    func testConnectedMatchingAccessoryBecomesBluetoothClassicCandidate() async throws {
        let snapshot = makeSnapshot()
        let discovery = IOSExternalAccessoryAdapterDiscovery(
            configuration: IOSExternalAccessoryProtocolConfiguration(
                protocolStrings: ["com.example.obd"]
            ),
            loadSnapshots: { [snapshot] }
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)
        let adapter = try XCTUnwrap(adapters.first)

        XCTAssertEqual(adapter.displayName, "OBDLink MX+")
        XCTAssertEqual(adapter.transportMode, .bluetooth)
        XCTAssertEqual(adapter.connectionTransport, .bluetoothClassic)
        XCTAssertTrue(adapter.isConnected)
        XCTAssertEqual(adapter.connectionState, .connected)
        XCTAssertNil(adapter.serialNumber)
        XCTAssertFalse(adapter.systemIdentifier.contains("MXPLUS-SERIAL"))
        XCTAssertTrue(adapter.systemIdentifier.hasPrefix("external-accessory:"))
    }

    /// 許可プロトコルがない場合に接続済み候補を公開しないことを検証します。
    ///
    /// 責務: 未確認プロトコルのExternalAccessoryがOBD候補へ混入しないことを確認します。
    func testUnconfiguredProtocolDoesNotExposeAccessory() async throws {
        let snapshot = makeSnapshot()
        let discovery = IOSExternalAccessoryAdapterDiscovery(
            configuration: IOSExternalAccessoryProtocolConfiguration(protocolStrings: []),
            loadSnapshots: { [snapshot] }
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertTrue(adapters.isEmpty)
    }

    /// 不一致プロトコルまたは未接続アクセサリーを候補から除外することを検証します。
    ///
    /// 責務: ExternalAccessory候補が接続状態とプロトコル許可の両条件を要求することを確認します。
    func testDiscoveryRejectsDisconnectedAndMismatchedAccessories() async throws {
        let disconnected = makeSnapshot(isConnected: false)
        let mismatched = IOSExternalAccessorySnapshot(
            connectionID: 43,
            name: "Other",
            manufacturer: "Other",
            modelNumber: "Other",
            serialNumber: "OTHER-SERIAL",
            protocolStrings: ["com.example.other"],
            isConnected: true
        )
        let discovery = IOSExternalAccessoryAdapterDiscovery(
            configuration: IOSExternalAccessoryProtocolConfiguration(
                protocolStrings: ["com.example.obd"]
            ),
            loadSnapshots: { [disconnected, mismatched] }
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertTrue(adapters.isEmpty)
    }

    /// テスト共通のMX+検出値を生成します。
    ///
    /// 責務: 接続状態だけを変更可能なExternalAccessoryテスト入力を構築します。
    /// - Parameter isConnected: iOSが報告する接続状態。
    /// - Returns: 許可プロトコルを公開するMX+相当スナップショット。
    private func makeSnapshot(isConnected: Bool = true) -> IOSExternalAccessorySnapshot {
        IOSExternalAccessorySnapshot(
            connectionID: 42,
            name: "OBDLink MX+",
            manufacturer: "OBD Solutions",
            modelNumber: "MX+",
            serialNumber: "MXPLUS-SERIAL",
            protocolStrings: ["com.example.obd"],
            isConnected: isConnected
        )
    }
}
#endif
