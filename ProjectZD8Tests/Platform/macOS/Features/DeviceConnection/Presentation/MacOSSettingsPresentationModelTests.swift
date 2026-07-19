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
        let preferencePort = DefaultAdapterPreferencePortFake()
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: port,
            preferencePort: preferencePort
        )

        model.send(.adapterSelectionRequested(.primary))
        await waitForDiscovery(in: model)
        model.send(.adapterCandidateSelected(adapter))
        model.send(.inspectedAdapterConfirmed)

        XCTAssertEqual(model.state.selectedAdapters[.primary], adapter)
        XCTAssertEqual(preferencePort.savedPreference, DefaultAdapterPreference(adapter: adapter))
        XCTAssertEqual(model.state.defaultAdapterPreference, DefaultAdapterPreference(adapter: adapter))
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
        let model = makeModel(
            state: state,
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [])
        )

        model.send(.inspectedAdapterDeclined)

        XCTAssertEqual(model.state.selectedAdapters[.primary], existing)
        XCTAssertNil(model.state.presentedAdapterSlot)
    }

    /// Bluetooth探索中でも選択モーダルをキャンセルできることを検証します。
    ///
    /// 責務: 完了していないBluetooth探索が設定画面のキャンセル操作を妨げないことを確認します。
    func testBluetoothDiscoveryDoesNotBlockSelectionCancellation() {
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: SuspendingSettingsAdapterDiscoveryPortFake()
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
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [adapter])
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
        let model = makeModel(
            state: state,
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [])
        )

        model.send(.inspectedAdapterConfirmed)

        XCTAssertNil(model.state.selectedAdapters[.secondary])
        XCTAssertTrue(model.state.hasAdapterAssignmentConflict)
        XCTAssertEqual(model.state.presentedAdapterSlot, .secondary)
    }

    /// 保存済みデフォルト候補が起動時探索で検出されるとプライマリーへ自動設定されることを検証します。
    ///
    /// 責務: デフォルト設定の復元と検出結果照合がユーザー再選択なしでプライマリー状態を作ることを確認します。
    func testSavedDefaultIsSelectedWhenDetectedAtLaunch() async {
        let adapter = makeAdapter(id: "saved", name: "Saved Adapter")
        let preferencePort = DefaultAdapterPreferencePortFake(
            loadedPreference: DefaultAdapterPreference(adapter: adapter)
        )
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [adapter]),
            preferencePort: preferencePort
        )

        await waitForDiscovery(in: model)

        XCTAssertEqual(model.state.defaultAdapterPreference, DefaultAdapterPreference(adapter: adapter))
        XCTAssertEqual(model.state.selectedAdapters[.primary], adapter)
    }

    /// 保存済みデフォルトと異なる候補を検出してもプライマリーへ自動設定しないことを検証します。
    ///
    /// 責務: 起動時探索が一致しない物理アダプターをデフォルト候補として扱わないことを確認します。
    func testDifferentDetectedAdapterDoesNotReplaceSavedDefault() async {
        let savedAdapter = makeAdapter(id: "saved", name: "Saved Adapter")
        let otherAdapter = makeAdapter(id: "other", name: "Other Adapter")
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [otherAdapter]),
            preferencePort: DefaultAdapterPreferencePortFake(
                loadedPreference: DefaultAdapterPreference(adapter: savedAdapter)
            )
        )

        await waitForDiscovery(in: model)

        XCTAssertNil(model.state.selectedAdapters[.primary])
        XCTAssertEqual(model.state.defaultAdapterPreference?.adapterID, "saved")
    }

    /// HOMEからの設定促進操作が注目要求番号を更新することを検証します。
    ///
    /// 責務: HOME由来の設定促進操作を設定カードの表示更新番号へ変換できることを確認します。
    func testAdapterAttentionRequestIncrementsSequence() {
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [])
        )

        model.send(.adapterAttentionRequested)

        XCTAssertEqual(model.state.adapterAttentionSequence, 1)
    }

    /// 表示済みの強調要求を消費すると手動再遷移の対象から外れることを検証します。
    ///
    /// 責務: macOS HOME由来の1件の強調要求を表示済み番号として保持し、未消費状態を残さないことを確認します。
    func testAdapterAttentionConsumptionPreventsManualReentryEmphasis() {
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [])
        )
        model.send(.adapterAttentionRequested)

        model.send(.adapterAttentionConsumed(1))

        XCTAssertEqual(model.state.adapterAttentionSequence, 1)
        XCTAssertEqual(model.state.consumedAdapterAttentionSequence, 1)
        XCTAssertFalse(model.state.hasPendingAdapterAttention)
    }

    /// 以前の強調を消費した後でも設定ボタンを再度押すと新しい強調要求になることを検証します。
    ///
    /// 責務: macOS HOMEの「アダプターを設定」を押すたびに異なる未消費要求が作られることを確認します。
    func testAdapterAttentionRequestAfterConsumptionCreatesNewEmphasis() {
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [])
        )
        model.send(.adapterAttentionRequested)
        model.send(.adapterAttentionConsumed(1))

        model.send(.adapterAttentionRequested)

        XCTAssertEqual(model.state.adapterAttentionSequence, 2)
        XCTAssertEqual(model.state.consumedAdapterAttentionSequence, 1)
        XCTAssertTrue(model.state.hasPendingAdapterAttention)
    }

    /// 古い強調要求の完了通知が最新要求を消費しないことを検証します。
    ///
    /// 責務: macOSの最新強調要求を過去画面から届いた完了通知から保護します。
    func testStaleAdapterAttentionConsumptionDoesNotConsumeLatestRequest() {
        let model = makeModel(
            state: MacOSSettingsState(),
            discoveryPort: SettingsAdapterDiscoveryPortFake(adapters: [])
        )
        model.send(.adapterAttentionRequested)
        model.send(.adapterAttentionRequested)

        model.send(.adapterAttentionConsumed(1))

        XCTAssertEqual(model.state.adapterAttentionSequence, 2)
        XCTAssertEqual(model.state.consumedAdapterAttentionSequence, 0)
        XCTAssertTrue(model.state.hasPendingAdapterAttention)
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

    /// 指定ポートを使用するmacOS設定プレゼンテーションモデルを生成します。
    ///
    /// 責務: macOS設定テスト用の探索境界と保存境界を1件のモデルへ注入します。
    /// - Parameters:
    ///   - state: モデルへ渡す初期表示状態。
    ///   - discoveryPort: 探索結果を提供するテスト用ポート。
    ///   - preferencePort: デフォルト設定を保持するテスト用ポート。
    /// - Returns: 指定したテスト境界を利用する設定プレゼンテーションモデル。
    private func makeModel(
        state: MacOSSettingsState,
        discoveryPort: any AdapterDiscoveryPort,
        preferencePort: DefaultAdapterPreferencePortFake = DefaultAdapterPreferencePortFake()
    ) -> MacOSSettingsPresentationModel {
        MacOSSettingsPresentationModel(
            state: state,
            latestDiscovery: LatestAdapterDiscoveryUseCase(
                discoverAdapters: DiscoverAdaptersUseCase(discoveryPort: discoveryPort)
            ),
            defaultAdapterPreference: DefaultAdapterPreferenceUseCase(
                preferencePort: preferencePort
            )
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

/// macOS設定テストでデフォルトアダプター設定を保持するFakeです。
private final class DefaultAdapterPreferencePortFake: DefaultAdapterPreferencePort {
    /// 読込要求へ返すデフォルト設定です。
    private let loadedPreference: DefaultAdapterPreference?

    /// 最後に保存されたデフォルト設定です。
    private(set) var savedPreference: DefaultAdapterPreference?

    /// 読込結果を注入してFakeを生成します。
    ///
    /// 責務: デフォルト設定テストへ返す読込結果を保持します。
    /// - Parameter loadedPreference: 読込要求へ返すデフォルト設定。
    init(loadedPreference: DefaultAdapterPreference? = nil) {
        self.loadedPreference = loadedPreference
    }

    /// 注入済みのデフォルト設定を返します。
    ///
    /// 責務: 1件の読込要求へ固定したデフォルト設定で応答します。
    /// - Returns: 初期化時に注入されたデフォルト設定。
    func load() -> DefaultAdapterPreference? {
        loadedPreference
    }

    /// 指定されたデフォルト設定をテスト観測用に保持します。
    ///
    /// 責務: 1件の保存要求を最後の保存設定として記録します。
    /// - Parameter preference: 保存要求で受け取ったデフォルト設定。
    func save(_ preference: DefaultAdapterPreference) {
        savedPreference = preference
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
