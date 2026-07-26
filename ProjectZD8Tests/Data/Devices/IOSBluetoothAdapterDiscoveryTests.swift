#if os(iOS)
import XCTest
@testable import ProjectZD8

/// iOSのBluetooth Classic候補とLow Energy候補の統合規則を検証します。
@MainActor
final class IOSBluetoothAdapterDiscoveryTests: XCTestCase {
    /// 2種類のBluetooth候補をExternalAccessory優先で統合することを検証します。
    ///
    /// 責務: ClassicとLow Energyの探索結果が入力順を保った単一一覧になることを確認します。
    func testDiscoveryMergesExternalAccessoryAndLowEnergyCandidates() async throws {
        let classic = makeAdapter(id: "classic", transport: .bluetoothClassic)
        let lowEnergy = makeAdapter(id: "ble", transport: .bluetoothLowEnergy)
        let discovery = IOSBluetoothAdapterDiscovery(
            externalAccessoryDiscovery: StubIOSAdapterDiscovery(result: .success([classic])),
            lowEnergyDiscovery: StubIOSAdapterDiscovery(result: .success([lowEnergy]))
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertEqual(adapters, [classic, lowEnergy])
    }

    /// BLE探索が失敗しても接続済みExternalAccessory候補を返すことを検証します。
    ///
    /// 責務: CoreBluetooth利用不可が有効なBluetooth Classic選択肢を消さないことを確認します。
    func testExternalAccessoryCandidateSurvivesLowEnergyFailure() async throws {
        let classic = makeAdapter(id: "classic", transport: .bluetoothClassic)
        let discovery = IOSBluetoothAdapterDiscovery(
            externalAccessoryDiscovery: StubIOSAdapterDiscovery(result: .success([classic])),
            lowEnergyDiscovery: StubIOSAdapterDiscovery(
                result: .failure(AdapterDiscoveryError.bluetoothPoweredOff)
            )
        )

        let adapters = try await discovery.discoverAdapters(for: .bluetooth)

        XCTAssertEqual(adapters, [classic])
    }

    /// Classic候補がない場合はBLE探索エラーを保持することを検証します。
    ///
    /// 責務: 代替候補のないBluetooth探索失敗が成功へ誤変換されないことを確認します。
    func testLowEnergyFailurePropagatesWithoutExternalAccessoryCandidate() async {
        let discovery = IOSBluetoothAdapterDiscovery(
            externalAccessoryDiscovery: StubIOSAdapterDiscovery(result: .success([])),
            lowEnergyDiscovery: StubIOSAdapterDiscovery(
                result: .failure(AdapterDiscoveryError.bluetoothPoweredOff)
            )
        )

        do {
            _ = try await discovery.discoverAdapters(for: .bluetooth)
            XCTFail("探索失敗が必要です")
        } catch let error as AdapterDiscoveryError {
            XCTAssertEqual(error, .bluetoothPoweredOff)
        } catch {
            XCTFail("想定外のエラーです: \(error)")
        }
    }

    /// 統合テスト用の接続済み候補を生成します。
    ///
    /// 責務: 識別子と物理終端だけが異なるBluetooth候補を構築します。
    /// - Parameters:
    ///   - id: 候補識別子。
    ///   - transport: OBD通信の物理終端。
    /// - Returns: 指定終端を持つ接続済みBluetooth候補。
    private func makeAdapter(
        id: String,
        transport: OBDConnectionEndpoint.Transport
    ) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .bluetooth,
            connectionTransport: transport,
            displayName: id,
            systemIdentifier: id,
            isConnected: true
        )
    }
}

/// 指定結果を返すiOS Bluetooth統合テスト用探索境界です。
@MainActor
private struct StubIOSAdapterDiscovery: AdapterDiscoveryPort {
    /// 探索時に返す候補またはエラーです。
    private let result: Result<[DiscoveredAdapter], AdapterDiscoveryError>

    /// 固定探索結果を持つ境界を生成します。
    ///
    /// 責務: 1件の探索結果をBluetooth統合テストへ注入します。
    /// - Parameter result: 探索時に返す候補またはエラー。
    init(result: Result<[DiscoveredAdapter], AdapterDiscoveryError>) {
        self.result = result
    }

    /// 注入済み探索結果を返します。
    ///
    /// 責務: 1回の探索要求を固定した成功または失敗へ変換します。
    /// - Parameter mode: テストでは結果に影響しない接続方式。
    /// - Returns: 注入済み候補一覧。
    /// - Throws: 注入済み探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        try result.get()
    }
}
#endif
