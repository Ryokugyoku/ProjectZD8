#if os(macOS)
import XCTest
@testable import ProjectZD8

/// macOS設定プレゼンテーションモデルの選択状態遷移を検証します。
@MainActor
final class MacOSSettingsPresentationModelTests: XCTestCase {
    /// 候補の詳細確認後にプライマリー設定として確定できることを検証します。
    ///
    /// 責務: 候補選択と確定操作がプライマリー設定へ反映されることを確認します。
    func testConfirmingInspectedAdapterSelectsPrimaryAdapter() async {
        let adapter = makeAdapter()
        let port = SettingsAdapterDiscoveryPortFake(adapters: [adapter])
        let model = MacOSSettingsPresentationModel(
            state: MacOSSettingsState(),
            latestDiscovery: makeLatestDiscovery(port: port)
        )

        model.send(.adapterSelectionRequested(.primary))
        await waitForDiscovery(in: model)
        model.send(.adapterCandidateSelected(adapter))
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
        var state = MacOSSettingsState()
        state.selectedAdapters[.primary] = existing
        state.presentedAdapterSlot = .primary
        state.inspectedAdapter = makeAdapter(id: "candidate", name: "Candidate")
        let model = MacOSSettingsPresentationModel(
            state: state,
            latestDiscovery: makeLatestDiscovery(
                port: SettingsAdapterDiscoveryPortFake(adapters: [])
            )
        )

        model.send(.inspectedAdapterDeclined)

        XCTAssertEqual(model.state.selectedAdapters[.primary], existing)
        XCTAssertNil(model.state.presentedAdapterSlot)
    }

    /// Bluetooth探索中でも選択モーダルをキャンセルできることを検証します。
    ///
    /// 責務: 完了していないBluetooth探索が設定画面のキャンセル操作を妨げないことを確認します。
    func testBluetoothDiscoveryDoesNotBlockSelectionCancellation() {
        let model = MacOSSettingsPresentationModel(
            state: MacOSSettingsState(),
            latestDiscovery: makeLatestDiscovery(
                port: SuspendingSettingsAdapterDiscoveryPortFake()
            )
        )

        model.send(.adapterSelectionRequested(.primary))
        model.send(.adapterTransportModeSelected(.bluetooth))

        XCTAssertEqual(model.state.adapterDiscoveryStatus, .searching)
        XCTAssertEqual(model.state.presentedAdapterSlot, .primary)

        model.send(.adapterSelectionCancelled)

        XCTAssertNil(model.state.presentedAdapterSlot)
    }

    /// セカンダリーでも共通候補フローから設定を確定できることを検証します。
    ///
    /// 責務: セカンダリー選択がプライマリーと同じ探索・詳細・確定経路を利用することを確認します。
    func testConfirmingInspectedAdapterSelectsSecondaryAdapter() async {
        let adapter = makeAdapter(id: "secondary", name: "Secondary")
        let model = MacOSSettingsPresentationModel(
            state: MacOSSettingsState(),
            latestDiscovery: makeLatestDiscovery(
                port: SettingsAdapterDiscoveryPortFake(adapters: [adapter])
            )
        )

        model.send(.adapterSelectionRequested(.secondary))
        await waitForDiscovery(in: model)
        model.send(.adapterCandidateSelected(adapter))
        model.send(.inspectedAdapterConfirmed)

        XCTAssertEqual(model.state.selectedAdapters[.secondary], adapter)
        XCTAssertNil(model.state.selectedAdapters[.primary])
        XCTAssertNil(model.state.presentedAdapterSlot)
    }

    /// 同じ物理アダプターを両方の接続役割へ割り当てられないことを検証します。
    ///
    /// 責務: プライマリー設定済み候補のセカンダリー二重割当を競合状態として拒否します。
    func testSamePhysicalAdapterCannotBeAssignedToBothSlots() {
        let adapter = makeAdapter()
        var state = MacOSSettingsState()
        state.selectedAdapters[.primary] = adapter
        state.presentedAdapterSlot = .secondary
        state.inspectedAdapter = adapter
        let model = MacOSSettingsPresentationModel(
            state: state,
            latestDiscovery: makeLatestDiscovery(
                port: SettingsAdapterDiscoveryPortFake(adapters: [])
            )
        )

        model.send(.inspectedAdapterConfirmed)

        XCTAssertNil(model.state.selectedAdapters[.secondary])
        XCTAssertTrue(model.state.hasAdapterAssignmentConflict)
        XCTAssertEqual(model.state.presentedAdapterSlot, .secondary)
    }

    /// 探索完了までモデルの状態変化を待機します。
    ///
    /// 責務: 非同期探索が完了するまでテストを限定回数だけ待機させます。
    /// - Parameter model: 探索状態を監視するプレゼンテーションモデル。
    private func waitForDiscovery(in model: MacOSSettingsPresentationModel) async {
        for _ in 0..<20 where model.state.adapterDiscoveryStatus == .searching {
            await Task.yield()
        }
    }

    /// 指定ポートを使用する最新探索ユースケースを生成します。
    ///
    /// 責務: macOS設定テスト用ポートを共通探索ライフサイクルへ結び付けます。
    /// - Parameter port: 探索結果を提供するテスト用ポート。
    /// - Returns: 指定ポートを利用する最新探索ユースケース。
    private func makeLatestDiscovery(
        port: any AdapterDiscoveryPort
    ) -> LatestAdapterDiscoveryUseCase {
        LatestAdapterDiscoveryUseCase(
            discoverAdapters: DiscoverAdaptersUseCase(discoveryPort: port)
        )
    }

    /// テストで使用するアダプター候補を生成します。
    ///
    /// 責務: 指定された識別子と名称を持つUSB候補を構築します。
    /// - Parameters:
    ///   - id: 候補の安定識別子。
    ///   - name: 候補の表示名。
    /// - Returns: プレゼンテーションテストで使用するUSB候補。
    private func makeAdapter(id: String = "candidate", name: String = "Adapter") -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .usb,
            displayName: name,
            systemIdentifier: id,
            isConnected: true
        )
    }
}

/// macOS設定テストへ固定候補を返す探索ポートです。
@MainActor
private final class SettingsAdapterDiscoveryPortFake: AdapterDiscoveryPort {
    /// 探索要求に対して返す候補です。
    private let adapters: [DiscoveredAdapter]

    /// 固定候補を注入してFakeを生成します。
    ///
    /// 責務: 設定画面テストへ返す候補一覧を保持します。
    /// - Parameter adapters: 探索要求に対して返す候補。
    init(adapters: [DiscoveredAdapter]) {
        self.adapters = adapters
    }

    /// 固定した候補一覧を返します。
    ///
    /// 責務: 1件の探索要求へ注入済み候補で応答します。
    /// - Parameter mode: 探索対象として要求された接続方式。
    /// - Returns: 初期化時に注入された候補。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        adapters
    }
}

/// キャンセルされるまで探索を完了しない設定画面テスト用ポートです。
@MainActor
private final class SuspendingSettingsAdapterDiscoveryPortFake: AdapterDiscoveryPort {
    /// キャンセルされるまで終了しない探索を実行します。
    ///
    /// 責務: 長時間継続するBluetooth探索をテストで再現します。
    /// - Parameter mode: 探索対象として要求された接続方式。
    /// - Returns: 通常は到達しない空の候補一覧。
    /// - Throws: テスト側から探索タスクをキャンセルした場合の `CancellationError`。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        try await Task.sleep(for: .seconds(60))
        return []
    }
}
#endif
