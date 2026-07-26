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
        let preferencePort = IOSDefaultAdapterPreferencePortFake()
        var state = IOSSettingsState()
        state.presentedAdapterSlot = .primary
        state.inspectedAdapter = adapter
        let model = makeModel(
            state: state,
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([])),
            preferencePort: preferencePort
        )

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

    /// 保存済みデフォルト候補が起動時Bluetooth探索で検出されるとプライマリーへ自動設定されることを検証します。
    ///
    /// 責務: iOSでのデフォルト設定復元と検出結果照合がユーザー再選択なしでプライマリー状態を作ることを確認します。
    func testSavedDefaultIsSelectedWhenDetectedAtLaunch() async {
        let adapter = makeAdapter(id: "saved", name: "Saved Adapter")
        let model = makeModel(
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([adapter])),
            preferencePort: IOSDefaultAdapterPreferencePortFake(
                loadedPreference: DefaultAdapterPreference(adapter: adapter)
            )
        )

        await waitForDiscovery(in: model)

        XCTAssertEqual(model.state.defaultAdapterPreference, DefaultAdapterPreference(adapter: adapter))
        XCTAssertEqual(model.state.selectedAdapters[.primary], adapter)
    }

    /// 保存済みデフォルトと同じ未接続Peripheralを接続前候補として復元することを検証します。
    ///
    /// 責務: iOS起動時探索がSwiftOBD2方式の未接続候補を保存済みデフォルトへ再照合することを確認します。
    func testDiscoveredSavedDefaultIsSelectedBeforeConnectionAtLaunch() async {
        let disconnectedAdapter = DiscoveredAdapter(
            id: "saved",
            transportMode: .bluetooth,
            displayName: "Saved Adapter",
            systemIdentifier: "saved",
            isConnected: false
        )
        let model = makeModel(
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([disconnectedAdapter])),
            preferencePort: IOSDefaultAdapterPreferencePortFake(
                loadedPreference: DefaultAdapterPreference(adapter: disconnectedAdapter)
            )
        )

        await waitForDiscovery(in: model)

        XCTAssertEqual(model.state.selectedAdapters[.primary], disconnectedAdapter)
        XCTAssertEqual(model.state.defaultAdapterPreference?.adapterID, "saved")
        XCTAssertEqual(model.state.discoveredAdapters, [disconnectedAdapter])
    }

    /// 保存済みデフォルトと異なるBluetooth候補を検出しても自動設定しないことを検証します。
    ///
    /// 責務: iOS起動時探索が一致しない候補をデフォルトアダプターとして扱わないことを確認します。
    func testDifferentDetectedAdapterDoesNotReplaceSavedDefault() async {
        let savedAdapter = makeAdapter(id: "saved", name: "Saved Adapter")
        let otherAdapter = makeAdapter(id: "other", name: "Other Adapter")
        let model = makeModel(
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([otherAdapter])),
            preferencePort: IOSDefaultAdapterPreferencePortFake(
                loadedPreference: DefaultAdapterPreference(adapter: savedAdapter)
            )
        )

        await waitForDiscovery(in: model)

        XCTAssertNil(model.state.selectedAdapters[.primary])
        XCTAssertEqual(model.state.defaultAdapterPreference?.adapterID, "saved")
    }

    /// 再探索で保存済みデフォルトを検出できない場合は以前のプライマリー割当を破棄します。
    ///
    /// 責務: 最新Bluetooth探索の空結果が古い検出済み状態をHOME向け設定状態へ残さないことを確認します。
    func testRefreshWithoutSavedDefaultClearsPreviouslyDetectedPrimary() async {
        let savedAdapter = makeAdapter(id: "saved", name: "Saved Adapter")
        var state = IOSSettingsState()
        state.defaultAdapterPreference = DefaultAdapterPreference(adapter: savedAdapter)
        state.selectedAdapters[.primary] = savedAdapter
        let model = makeModel(
            state: state,
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([]))
        )

        model.send(.bluetoothRefreshRequested)
        await waitForDiscovery(in: model)

        XCTAssertNil(model.state.selectedAdapters[.primary])
        XCTAssertEqual(model.state.defaultAdapterPreference?.adapterID, "saved")
    }

    /// HOMEからの設定促進操作が注目要求番号を更新することを検証します。
    ///
    /// 責務: iOS HOME由来の設定促進操作を設定カードの表示更新番号へ変換できることを確認します。
    func testAdapterAttentionRequestIncrementsSequence() {
        let model = makeModel(
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([]))
        )

        model.send(.adapterAttentionRequested)

        XCTAssertEqual(model.state.adapterAttentionSequence, 1)
    }

    /// 表示済みの強調要求を消費すると手動再遷移の対象から外れることを検証します。
    ///
    /// 責務: iOS HOME由来の1件の強調要求を表示済み番号として保持し、未消費状態を残さないことを確認します。
    func testAdapterAttentionConsumptionPreventsManualReentryEmphasis() {
        let model = makeModel(
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([]))
        )
        model.send(.adapterAttentionRequested)

        model.send(.adapterAttentionConsumed(1))

        XCTAssertEqual(model.state.adapterAttentionSequence, 1)
        XCTAssertEqual(model.state.consumedAdapterAttentionSequence, 1)
        XCTAssertFalse(model.state.hasPendingAdapterAttention)
    }

    /// 以前の強調を消費した後でも設定ボタンを再度押すと新しい強調要求になることを検証します。
    ///
    /// 責務: iOS HOMEの「アダプターを設定」を押すたびに異なる未消費要求が作られることを確認します。
    func testAdapterAttentionRequestAfterConsumptionCreatesNewEmphasis() {
        let model = makeModel(
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([]))
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
    /// 責務: iOSの最新強調要求を過去画面から届いた完了通知から保護します。
    func testStaleAdapterAttentionConsumptionDoesNotConsumeLatestRequest() {
        let model = makeModel(
            port: ImmediateIOSAdapterDiscoveryPortFake(result: .success([]))
        )
        model.send(.adapterAttentionRequested)
        model.send(.adapterAttentionRequested)

        model.send(.adapterAttentionConsumed(1))

        XCTAssertEqual(model.state.adapterAttentionSequence, 2)
        XCTAssertEqual(model.state.consumedAdapterAttentionSequence, 0)
        XCTAssertTrue(model.state.hasPendingAdapterAttention)
    }

    /// テスト対象モデルを指定したStateと探索ポートで生成します。
    ///
    /// 責務: 1件のiOS設定テスト用依存関係を構築します。
    /// - Parameters:
    ///   - state: モデルへ渡す初期表示状態。省略時は既定状態を使用します。
    ///   - port: 探索結果を制御するテスト用ポート。
    ///   - preferencePort: デフォルト設定を保持するテスト用ポート。
    /// - Returns: 注入済みのiOS設定プレゼンテーションモデル。
    private func makeModel(
        state: IOSSettingsState? = nil,
        port: any AdapterDiscoveryPort,
        preferencePort: IOSDefaultAdapterPreferencePortFake = IOSDefaultAdapterPreferencePortFake()
    ) -> IOSSettingsPresentationModel {
        let discoverAdapters = DiscoverAdaptersUseCase(discoveryPort: port)
        return IOSSettingsPresentationModel(
            state: state ?? IOSSettingsState(),
            latestDiscovery: LatestAdapterDiscoveryUseCase(discoverAdapters: discoverAdapters),
            defaultAdapterPreference: DefaultAdapterPreferenceUseCase(
                preferencePort: preferencePort
            )
        )
    }

    /// テストで使うBluetooth候補を生成します。
    ///
    /// 責務: 指定された識別子と名称を持つ未接続BLE候補を構築します。
    /// - Parameters:
    ///   - id: 候補の安定識別子。
    ///   - name: 候補の表示名。
    /// - Returns: プレゼンテーションテストで使用する接続済みBluetooth候補。
    private func makeAdapter(id: String, name: String) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .bluetooth,
            displayName: name,
            systemIdentifier: id,
            isConnected: true
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

/// iOS設定テストでデフォルトアダプター設定を保持するFakeです。
private final class IOSDefaultAdapterPreferencePortFake: DefaultAdapterPreferencePort {
    /// 読込要求へ返すデフォルト設定です。
    private let loadedPreference: DefaultAdapterPreference?

    /// 最後に保存されたデフォルト設定です。
    private(set) var savedPreference: DefaultAdapterPreference?

    /// 読込結果を注入してFakeを生成します。
    ///
    /// 責務: iOSデフォルト設定テストへ返す読込結果を保持します。
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
