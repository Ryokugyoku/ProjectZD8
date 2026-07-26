import XCTest
@testable import ProjectZD8

/// アダプター探索ユースケースの候補整形を検証します。
@MainActor
final class DiscoverAdaptersUseCaseTests: XCTestCase {
    /// 重複候補を除去して表示名順に整列することを検証します。
    ///
    /// 責務: 探索ポートの重複した結果が安定した候補一覧へ変換されることを確認します。
    func testExecuteRemovesDuplicatesAndSortsByDisplayName() async throws {
        let later = makeAdapter(id: "later", name: "Zulu")
        let earlier = makeAdapter(id: "earlier", name: "Alpha")
        let port = AdapterDiscoveryPortFake(adapters: [later, earlier, later])
        let useCase = DiscoverAdaptersUseCase(discoveryPort: port)

        let result = try await useCase.execute(for: .usb)

        XCTAssertEqual(result.map(\.id), ["earlier", "later"])
        XCTAssertEqual(port.requestedModes, [.usb])
    }

    /// 同一Peripheral UUIDのBluetooth候補を1件へまとめることを検証します。
    ///
    /// 責務: 同じ安定識別子を持つ重複BLE通知が1件の探索結果になることを確認します。
    func testExecuteMergesDuplicateBluetoothPeripheralIdentifiers() async throws {
        let identifier = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let first = DiscoveredAdapter(
            id: "bluetooth-low-energy:\(identifier)",
            transportMode: .bluetooth,
            displayName: "Adapter",
            systemIdentifier: identifier,
            isConnected: true
        )
        let duplicate = DiscoveredAdapter(
            id: "bluetooth-low-energy:\(identifier)",
            transportMode: .bluetooth,
            displayName: "Adapter Duplicate",
            systemIdentifier: identifier,
            isConnected: true
        )
        let port = AdapterDiscoveryPortFake(adapters: [first, duplicate])
        let useCase = DiscoverAdaptersUseCase(discoveryPort: port)

        let result = try await useCase.execute(for: .bluetooth)

        XCTAssertEqual(result, [first])
        XCTAssertEqual(port.requestedModes, [.bluetooth])
    }

    /// Bluetooth探索結果から未接続候補を除外することを検証します。
    ///
    /// 責務: Bluetooth選択一覧が接続済みと確認できた候補だけを返すことを確認します。
    func testExecuteExcludesDisconnectedBluetoothCandidates() async throws {
        let connected = DiscoveredAdapter(
            id: "connected",
            transportMode: .bluetooth,
            displayName: "Connected",
            systemIdentifier: "connected",
            isConnected: true
        )
        let disconnected = DiscoveredAdapter(
            id: "disconnected",
            transportMode: .bluetooth,
            displayName: "Disconnected",
            systemIdentifier: "disconnected",
            isConnected: false
        )
        let port = AdapterDiscoveryPortFake(adapters: [disconnected, connected])
        let useCase = DiscoverAdaptersUseCase(discoveryPort: port)

        let result = try await useCase.execute(for: .bluetooth)

        XCTAssertEqual(result, [connected])
        XCTAssertEqual(port.requestedModes, [.bluetooth])
    }

    /// テストで使用する最小のアダプター候補を生成します。
    ///
    /// 責務: 指定された識別子と表示名を持つUSB候補をテスト入力として構築します。
    /// - Parameters:
    ///   - id: 候補の安定識別子。
    ///   - name: 候補の表示名。
    /// - Returns: USB接続済みとして扱うテスト候補。
    private func makeAdapter(id: String, name: String) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .usb,
            displayName: name,
            systemIdentifier: id,
            isConnected: true
        )
    }
}

/// テストで決定的な候補一覧を返すアダプター探索ポートです。
@MainActor
private final class AdapterDiscoveryPortFake: AdapterDiscoveryPort {
    /// 探索結果として返す候補です。
    private let adapters: [DiscoveredAdapter]

    /// ユースケースから要求された接続方式です。
    private(set) var requestedModes: [AdapterTransportMode] = []

    /// 固定の探索結果を注入してFakeを生成します。
    ///
    /// 責務: 1件のテストシナリオで返す候補一覧を保持します。
    /// - Parameter adapters: 探索要求に対して返す候補。
    init(adapters: [DiscoveredAdapter]) {
        self.adapters = adapters
    }

    /// 要求された接続方式を記録して固定候補を返します。
    ///
    /// 責務: 1件の探索要求を記録し、注入済みの候補一覧で応答します。
    /// - Parameter mode: 探索対象として要求された接続方式。
    /// - Returns: 初期化時に注入された候補。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        requestedModes.append(mode)
        return adapters
    }
}
