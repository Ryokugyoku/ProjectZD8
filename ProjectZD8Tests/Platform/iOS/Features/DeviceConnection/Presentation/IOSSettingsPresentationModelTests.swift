#if os(iOS)
import XCTest
@testable import ProjectZD8

/// iOS設定プレゼンテーションモデルのBluetooth選択状態遷移を検証します。
@MainActor
final class IOSSettingsPresentationModelTests: XCTestCase {
    /// プライマリー設定操作がBluetooth専用選択画面と探索を開始することを検証します。
    ///
    /// 責務: プライマリー行の型付き操作が選択表示と非同期探索状態へ遷移することを確認します。
    func testPrimaryAdapterRequestPresentsBluetoothSelection() {
        let model = makeModel(port: SuspendingIOSAdapterDiscoveryPortFake())

        model.send(.adapterSelectionRequested(.primary))

        XCTAssertEqual(model.state.presentedAdapterSlot, .primary)
        XCTAssertEqual(model.state.bluetoothDiscoveryStatus, .searching)
    }

    /// Bluetooth探索中でも選択画面をキャンセルできることを検証します。
    ///
    /// 責務: 完了していないBLE探索がキャンセル操作を妨げないことを確認します。
    func testSearchingSelectionCanBeCancelled() {
        let model = makeModel(port: SuspendingIOSAdapterDiscoveryPortFake())
        model.send(.adapterSelectionRequested(.primary))

        model.send(.adapterSelectionCancelled)

        XCTAssertNil(model.state.presentedAdapterSlot)
        XCTAssertNil(model.state.inspectedAdapter)
    }

    /// 詳細確認した候補をプライマリー選択状態へ反映できることを検証します。
    ///
    /// 責務: 候補確定操作が選択状態だけを更新して選択画面を閉じることを確認します。
    func testConfirmingCandidateSelectsPrimaryAdapter() {
        let adapter = makeAdapter(id: "candidate", name: "Candidate")
        var state = IOSSettingsState()
        state.presentedAdapterSlot = .primary
        state.inspectedAdapter = adapter
        let model = makeModel(state: state, port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([])))

        model.send(.inspectedAdapterConfirmed)

        XCTAssertEqual(model.state.selectedAdapters[.primary], adapter)
        XCTAssertNil(model.state.presentedAdapterSlot)
        XCTAssertNil(model.state.inspectedAdapter)
    }

    /// 「設定しない」で既存のプライマリー設定を維持することを検証します。
    ///
    /// 責務: 候補の設定中止が既存のプライマリーアダプターを変更しないことを確認します。
    func testDecliningCandidatePreservesExistingPrimaryAdapter() {
        let existing = makeAdapter(id: "existing", name: "Existing")
        var state = IOSSettingsState()
        state.selectedAdapters[.primary] = existing
        state.presentedAdapterSlot = .primary
        state.inspectedAdapter = makeAdapter(id: "candidate", name: "Candidate")
        let model = makeModel(state: state, port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([])))

        model.send(.inspectedAdapterDeclined)

        XCTAssertEqual(model.state.selectedAdapters[.primary], existing)
        XCTAssertNil(model.state.presentedAdapterSlot)
    }

    /// 詳細確認した候補をセカンダリー選択状態だけへ反映できることを検証します。
    ///
    /// 責務: 共通候補確定操作がセカンダリーを更新し既存プライマリーを維持することを確認します。
    func testConfirmingCandidateSelectsSecondaryAdapterOnly() {
        let primary = makeAdapter(id: "primary", name: "Primary")
        let secondary = makeAdapter(id: "secondary", name: "Secondary")
        var state = IOSSettingsState()
        state.selectedAdapters[.primary] = primary
        state.presentedAdapterSlot = .secondary
        state.inspectedAdapter = secondary
        let model = makeModel(state: state, port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([])))

        model.send(.inspectedAdapterConfirmed)

        XCTAssertEqual(model.state.selectedAdapters[.primary], primary)
        XCTAssertEqual(model.state.selectedAdapters[.secondary], secondary)
        XCTAssertNil(model.state.presentedAdapterSlot)
        XCTAssertNil(model.state.inspectedAdapter)
    }

    /// セカンダリーで「設定しない」を選ぶと既存設定を維持することを検証します。
    ///
    /// 責務: 共通候補の設定中止が既存セカンダリーアダプターを変更しないことを確認します。
    func testDecliningCandidatePreservesExistingSecondaryAdapter() {
        let existing = makeAdapter(id: "existing-secondary", name: "Existing Secondary")
        var state = IOSSettingsState()
        state.selectedAdapters[.secondary] = existing
        state.presentedAdapterSlot = .secondary
        state.inspectedAdapter = makeAdapter(id: "candidate", name: "Candidate")
        let model = makeModel(state: state, port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([])))

        model.send(.inspectedAdapterDeclined)

        XCTAssertEqual(model.state.selectedAdapters[.secondary], existing)
        XCTAssertNil(model.state.presentedAdapterSlot)
    }

    /// 同じ物理アダプターを両方の接続役割へ割り当てられないことを検証します。
    ///
    /// 責務: プライマリー設定済み候補のセカンダリー二重割当を競合状態として拒否します。
    func testSamePhysicalAdapterCannotBeAssignedToBothRoles() {
        let adapter = makeAdapter(id: "shared", name: "Shared")
        var state = IOSSettingsState()
        state.selectedAdapters[.primary] = adapter
        state.presentedAdapterSlot = .secondary
        state.inspectedAdapter = adapter
        let model = makeModel(state: state, port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([])))

        model.send(.inspectedAdapterConfirmed)

        XCTAssertNil(model.state.selectedAdapters[.secondary])
        XCTAssertTrue(model.state.hasAdapterAssignmentConflict)
        XCTAssertEqual(model.state.presentedAdapterSlot, .secondary)
    }

    /// Bluetooth OFF、未許可、非対応を別々の表示状態へ変換することを検証します。
    ///
    /// 責務: 3種類のCoreBluetooth利用不可理由が空一覧や相互に同じ状態へ崩れないことを確認します。
    func testBluetoothUnavailableReasonsRemainDistinct() async {
        let scenarios: [(AdapterDiscoveryError, IOSBluetoothDiscoveryStatus)] = [
            (.bluetoothPoweredOff, .unavailable(.poweredOff)),
            (.bluetoothUnauthorized, .unavailable(.unauthorized)),
            (.bluetoothUnsupported, .unavailable(.unsupported))
        ]

        for (error, expectedStatus) in scenarios {
            let model = makeModel(port: ImmediateIOSAdapterDiscoveryPortFake(result: .failure(error)))
            model.send(.adapterSelectionRequested(.primary))
            await waitForDiscovery(in: model)
            XCTAssertEqual(model.state.bluetoothDiscoveryStatus, expectedStatus)
            XCTAssertTrue(model.state.discoveredAdapters.isEmpty)
        }
    }

    /// 古い探索結果が再探索後のStateへ反映されないことを検証します。
    ///
    /// 責務: キャンセルに即応しない以前の探索完了が最新候補を上書きしないことを確認します。
    func testStaleDiscoveryResultDoesNotReplaceCurrentState() async {
        let oldAdapter = makeAdapter(id: "old", name: "Old")
        let currentAdapter = makeAdapter(id: "current", name: "Current")
        let port = ControlledIOSAdapterDiscoveryPortFake()
        let model = makeModel(port: port)

        model.send(.adapterSelectionRequested(.primary))
        await waitForRequestCount(1, in: port)
        model.send(.bluetoothRefreshRequested)
        await waitForRequestCount(2, in: port)

        port.completeRequest(at: 1, with: [currentAdapter])
        await waitForDiscovery(in: model)
        port.completeRequest(at: 0, with: [oldAdapter])
        await Task.yield()

        XCTAssertEqual(model.state.discoveredAdapters, [currentAdapter])
        XCTAssertEqual(model.state.bluetoothDiscoveryStatus, .loaded)
    }

    /// テスト対象モデルを指定したStateと探索ポートで生成します。
    ///
    /// 責務: 1件のiOS設定テスト用依存関係を構築します。
    /// - Parameters:
    ///   - state: モデルへ渡す初期表示状態。省略時は既定状態を使用します。
    ///   - port: 探索結果を制御するテスト用ポート。
    /// - Returns: 注入済みのiOS設定プレゼンテーションモデル。
    private func makeModel(
        state: IOSSettingsState? = nil,
        port: any AdapterDiscoveryPort
    ) -> IOSSettingsPresentationModel {
        let discoverAdapters = DiscoverAdaptersUseCase(discoveryPort: port)
        return IOSSettingsPresentationModel(
            state: state ?? IOSSettingsState(),
            latestDiscovery: LatestAdapterDiscoveryUseCase(discoverAdapters: discoverAdapters)
        )
    }

    /// テストで使うBluetooth候補を生成します。
    ///
    /// 責務: 指定された識別子と名称を持つ未接続BLE候補を構築します。
    /// - Parameters:
    ///   - id: 候補の安定識別子。
    ///   - name: 候補の表示名。
    /// - Returns: プレゼンテーションテストで使用するBluetooth候補。
    private func makeAdapter(id: String, name: String) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .bluetooth,
            displayName: name,
            systemIdentifier: id,
            isConnected: false
        )
    }

    /// 探索状態が検索中以外へ変わるまで限定回数待機します。
    ///
    /// 責務: 非同期探索の状態反映をテスト内で決定的に待機します。
    /// - Parameter model: 探索状態を監視するプレゼンテーションモデル。
    private func waitForDiscovery(in model: IOSSettingsPresentationModel) async {
        for _ in 0..<40 where model.state.bluetoothDiscoveryStatus == .searching {
            await Task.yield()
        }
    }

    /// 制御可能Fakeが指定件数の要求を受け取るまで限定回数待機します。
    ///
    /// 責務: 再探索テストで必要な継続が登録されるまで待機します。
    /// - Parameters:
    ///   - expectedCount: 待機する探索要求件数。
    ///   - port: 要求数を監視する制御可能Fake。
    private func waitForRequestCount(
        _ expectedCount: Int,
        in port: ControlledIOSAdapterDiscoveryPortFake
    ) async {
        for _ in 0..<40 where port.requestCount < expectedCount {
            await Task.yield()
        }
        XCTAssertEqual(port.requestCount, expectedCount)
    }
}

/// 固定結果または固定エラーを直ちに返すiOS探索Fakeです。
@MainActor
private final class ImmediateIOSAdapterDiscoveryPortFake: AdapterDiscoveryPort {
    /// 探索要求へ返す固定結果です。
    private let result: Result<[DiscoveredAdapter], AdapterDiscoveryError>

    /// 固定結果を注入してFakeを生成します。
    ///
    /// 責務: 1件のiOS設定テストで返す探索結果を保持します。
    /// - Parameter result: 探索要求へ返す候補一覧またはエラー。
    init(result: Result<[DiscoveredAdapter], AdapterDiscoveryError>) {
        self.result = result
    }

    /// 注入済みの固定探索結果を返します。
    ///
    /// 責務: 1件の探索要求へ固定した候補一覧またはエラーで応答します。
    /// - Parameter mode: 探索対象として要求された接続方式。
    /// - Returns: 注入済みの候補一覧。
    /// - Throws: 注入済みの探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        try result.get()
    }
}

/// キャンセルされるまで探索を完了しないiOS探索Fakeです。
@MainActor
private final class SuspendingIOSAdapterDiscoveryPortFake: AdapterDiscoveryPort {
    /// キャンセルされるまで終了しないBluetooth探索を実行します。
    ///
    /// 責務: 長時間継続するBLE探索をiOS設定テストで再現します。
    /// - Parameter mode: 探索対象として要求された接続方式。
    /// - Returns: 通常は到達しない空の候補一覧。
    /// - Throws: 探索タスクをキャンセルした場合の `CancellationError`。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        try await Task.sleep(for: .seconds(60))
        return []
    }
}

/// 探索完了順をテストから制御するiOS探索Fakeです。
@MainActor
private final class ControlledIOSAdapterDiscoveryPortFake: AdapterDiscoveryPort {
    /// 未完了の探索継続を要求順に保持します。
    private var continuations: [CheckedContinuation<[DiscoveredAdapter], Never>] = []

    /// 受け取った探索要求件数です。
    var requestCount: Int { continuations.count }

    /// テストから完了されるまで探索結果を保留します。
    ///
    /// 責務: 1件の探索要求を順序付き継続として記録します。
    /// - Parameter mode: 探索対象として要求された接続方式。
    /// - Returns: テストから指定された時点の候補一覧。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    /// 指定順の探索要求を候補一覧で完了します。
    ///
    /// 責務: 1件の保留中探索へテスト指定の候補一覧を返します。
    /// - Parameters:
    ///   - index: 完了する探索要求の順序。
    ///   - adapters: 探索結果として返す候補一覧。
    func completeRequest(at index: Int, with adapters: [DiscoveredAdapter]) {
        continuations[index].resume(returning: adapters)
    }
}
#endif
