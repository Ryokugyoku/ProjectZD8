#if os(macOS)
import XCTest
@testable import ProjectZD8

/// 保存済みプライマリー設定がある時のmacOS設定表示(選択済み表示と検出状態)を検証します。
@MainActor
final class MacOSSettingsPresentationModelSavedPrimaryTests: XCTestCase {
    /// 探索が空・利用不可・失敗でも、保存済みプライマリーは保存名で選択済み・未検出になることを検証します。
    ///
    /// 責務: 再起動後に広告が見えない場合でも「未選択」にならず、「検出済み」「接続中」とも表示しないことを確認します。
    func testSavedPrimaryStaysSelectedButNotDetectedWhenDiscoveryFindsNothing() async {
        let outcomes: [Result<[DiscoveredAdapter], AdapterDiscoveryError>] = [
            .success([]),
            .failure(.bluetoothPoweredOff),
            .failure(.bluetoothUnauthorized),
            .failure(.bluetoothUnsupported),
            .failure(.bluetoothStateUnavailable)
        ]

        for outcome in outcomes {
            let model = makeModel(result: outcome, saved: savedAdapter())
            await waitForDiscovery(in: model)

            XCTAssertEqual(describePrimary(of: model), .adapterName("Saved Adapter"), "結果: \(outcome)")
            let home = MacOSHomeState(settingsState: model.state)
            XCTAssertEqual(home.defaultAdapterAvailability, .notDetected(displayName: "Saved Adapter"), "結果: \(outcome)")
            XCTAssertNil(home.defaultAdapterAvailability.connectionEndpoint, "結果: \(outcome)")
        }
    }

    /// 一致する候補が見つかれば検出済みになり、手動接続の接続先を作ることを検証します。
    ///
    /// 責務: 検出済みの時だけ接続先ができる既存の挙動を回帰で守ります。
    func testMatchingCandidateIsDetectedWithEndpoint() async {
        let adapter = savedAdapter()
        let model = makeModel(result: .success([adapter]), saved: adapter)

        await waitForDiscovery(in: model)

        XCTAssertEqual(describePrimary(of: model), .adapterName("Saved Adapter"))
        let home = MacOSHomeState(settingsState: model.state)
        XCTAssertEqual(home.defaultAdapterAvailability.connectionEndpoint, OBDConnectionEndpoint(adapter: adapter))
        XCTAssertTrue(home.defaultAdapterAvailability.isDetected)
    }

    /// 保存済み設定が無ければ、探索結果にかかわらず未選択になることを検証します。
    ///
    /// 責務: 設定が無い時のプライマリーが未選択・未設定のままであることを確認します。
    func testNoSavedPreferenceIsNotSelected() async {
        let model = makeModel(result: .success([savedAdapter()]), saved: nil)

        await waitForDiscovery(in: model)

        XCTAssertEqual(describePrimary(of: model), .localizationKey(AdapterSlotSettingsDescription.notSelectedKey))
        XCTAssertEqual(MacOSHomeState(settingsState: model.state).defaultAdapterAvailability, .notConfigured)
    }

    /// 設定画面のプライマリー行の説明を、モデルの現在状態から求めます。
    ///
    /// 責務: 画面が使う純粋型へモデルの状態を渡した結果を返します。
    /// - Parameter model: 観測するプレゼンテーションモデル。
    /// - Returns: プライマリー行の説明。
    private func describePrimary(of model: MacOSSettingsPresentationModel) -> AdapterSlotSettingsDescription {
        AdapterSlotSettingsDescription(
            slot: .primary,
            selectedAdapters: model.state.selectedAdapters,
            defaultAdapterPreference: model.state.defaultAdapterPreference
        )
    }

    /// 保存済みアダプターに対応する検出候補を作ります。
    ///
    /// 責務: 保存設定と一致するUSB候補を返します。
    /// - Returns: テスト用のUSB候補。
    private func savedAdapter() -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: "saved",
            transportMode: .usb,
            displayName: "Saved Adapter",
            systemIdentifier: "saved",
            isConnected: false
        )
    }

    /// 探索結果と保存設定を指定してモデルを生成します。
    ///
    /// 責務: 固定の探索結果と保存設定を注入した設定モデルを構築します。
    /// - Parameters:
    ///   - result: 探索が返す候補またはエラー。
    ///   - saved: 保存済みとして復元する候補。nilなら設定なし。
    /// - Returns: 注入済みのモデル。
    private func makeModel(
        result: Result<[DiscoveredAdapter], AdapterDiscoveryError>,
        saved: DiscoveredAdapter?
    ) -> MacOSSettingsPresentationModel {
        MacOSSettingsPresentationModel(
            state: MacOSSettingsState(),
            latestDiscovery: LatestAdapterDiscoveryUseCase(
                discoverAdapters: DiscoverAdaptersUseCase(discoveryPort: MacOSSavedPrimaryDiscoveryPortFake(result: result))
            ),
            defaultAdapterPreference: DefaultAdapterPreferenceUseCase(
                preferencePort: MacOSSavedPrimaryPreferencePortFake(preference: saved.map(DefaultAdapterPreference.init(adapter:)))
            )
        )
    }

    /// 探索状態が検索中以外になるまで、上限付きで待機します。
    ///
    /// 責務: 上限内に探索が完了しなければ失敗として報告します。
    /// - Parameter model: 監視するモデル。
    private func waitForDiscovery(in model: MacOSSettingsPresentationModel) async {
        for _ in 0..<200 where model.state.adapterDiscoveryStatus == .searching {
            await Task.yield()
        }
        if model.state.adapterDiscoveryStatus == .searching {
            XCTFail("探索が上限内に完了しませんでした")
        }
    }
}

/// 固定結果を直ちに返す探索Fakeです。
@MainActor
private final class MacOSSavedPrimaryDiscoveryPortFake: AdapterDiscoveryPort {
    /// 返す固定結果です。
    private let result: Result<[DiscoveredAdapter], AdapterDiscoveryError>

    /// 固定結果を注入します。
    ///
    /// 責務: 返す結果を保持します。
    /// - Parameter result: 返す候補またはエラー。
    init(result: Result<[DiscoveredAdapter], AdapterDiscoveryError>) {
        self.result = result
    }

    /// 固定結果を返します。
    ///
    /// 責務: 探索要求へ注入済みの結果で応答します。
    /// - Parameter mode: 要求された接続方式。
    /// - Returns: 候補一覧。
    /// - Throws: 注入済みの探索エラー。
    func discoverAdapters(for mode: AdapterTransportMode) async throws -> [DiscoveredAdapter] {
        try result.get()
    }
}

/// 固定の保存設定を返す保存Fakeです。
private final class MacOSSavedPrimaryPreferencePortFake: DefaultAdapterPreferencePort {
    /// 読込へ返す設定です。
    private let preference: DefaultAdapterPreference?

    /// 設定を注入します。
    ///
    /// 責務: 返す設定を保持します。
    /// - Parameter preference: 読込へ返す設定。
    init(preference: DefaultAdapterPreference?) {
        self.preference = preference
    }

    /// 固定の設定を返します。
    ///
    /// 責務: 読込要求へ注入済みの設定で応答します。
    /// - Returns: 保存済み設定。
    func load() -> DefaultAdapterPreference? {
        preference
    }

    /// 保存要求を無視します。
    ///
    /// 責務: このテストでは保存を使わないため何もしません。
    /// - Parameter preference: 保存要求の設定。
    func save(_ preference: DefaultAdapterPreference) {}
}
#endif
