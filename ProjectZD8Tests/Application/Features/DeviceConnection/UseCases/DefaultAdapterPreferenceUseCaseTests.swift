import XCTest
@testable import ProjectZD8

/// 共通デフォルトアダプター設定ユースケースの保存と照合を検証します。
@MainActor
final class DefaultAdapterPreferenceUseCaseTests: XCTestCase {
    /// 保存境界から既存のデフォルト設定を復元できることを検証します。
    ///
    /// 責務: 共通ユースケースの読込が保存境界の値を変更せず返すことを確認します。
    func testLoadReturnsStoredPreference() {
        let adapter = makeAdapter(id: "saved", name: "Saved Adapter")
        let expected = DefaultAdapterPreference(adapter: adapter)
        let port = DefaultAdapterPreferencePortFake(loadedPreference: expected)
        let useCase = DefaultAdapterPreferenceUseCase(preferencePort: port)

        XCTAssertEqual(useCase.load(), expected)
    }

    /// 検出済み候補をデフォルト設定へ変換して保存できることを検証します。
    ///
    /// 責務: 共通ユースケースが確定候補の識別情報を保存境界へ1件渡すことを確認します。
    func testSavePersistsDetectedAdapterPreference() {
        let adapter = makeAdapter(id: "candidate", name: "Candidate")
        let port = DefaultAdapterPreferencePortFake()
        let useCase = DefaultAdapterPreferenceUseCase(preferencePort: port)

        let saved = useCase.save(adapter: adapter)

        XCTAssertEqual(saved, DefaultAdapterPreference(adapter: adapter))
        XCTAssertEqual(port.savedPreference, saved)
    }

    /// 保存済み識別情報と一致する最新候補だけを返すことを検証します。
    ///
    /// 責務: 共通ユースケースが異なる候補を除外して同一候補を選択することを確認します。
    func testDetectedAdapterReturnsOnlyMatchingCandidate() {
        let expected = makeAdapter(id: "saved", name: "Detected Name")
        let different = makeAdapter(id: "other", name: "Other")
        let preference = DefaultAdapterPreference(adapter: expected)
        let useCase = DefaultAdapterPreferenceUseCase(
            preferencePort: DefaultAdapterPreferencePortFake()
        )

        let result = useCase.detectedAdapter(matching: preference, in: [different, expected])

        XCTAssertEqual(result, expected)
    }

    /// テストで使用するBluetoothアダプター候補を生成します。
    ///
    /// 責務: 指定された識別子と表示名を持つ候補を1件構築します。
    /// - Parameters:
    ///   - id: 候補を識別する安定識別子。
    ///   - name: 候補の表示名。
    /// - Returns: 未接続状態のBluetooth候補。
    private func makeAdapter(id: String, name: String) -> DiscoveredAdapter {
        DiscoveredAdapter(
            id: id,
            transportMode: .bluetooth,
            displayName: name,
            systemIdentifier: id,
            isConnected: false
        )
    }
}

/// 共通ユースケーステストで保存内容を観測する保存境界です。
private final class DefaultAdapterPreferencePortFake: DefaultAdapterPreferencePort {
    /// 読込時に返す既存設定です。
    private let loadedPreference: DefaultAdapterPreference?

    /// 最後に保存された設定です。
    private(set) var savedPreference: DefaultAdapterPreference?

    /// 読込用の既存設定を注入してFakeを生成します。
    ///
    /// 責務: 1件のテストシナリオで返す既存設定を保持します。
    /// - Parameter loadedPreference: 読込要求時に返す設定。
    init(loadedPreference: DefaultAdapterPreference? = nil) {
        self.loadedPreference = loadedPreference
    }

    /// 注入済みの既存設定を返します。
    ///
    /// 責務: デフォルト設定の読込要求へ固定値で応答します。
    /// - Returns: 初期化時に注入された設定。
    func load() -> DefaultAdapterPreference? {
        loadedPreference
    }

    /// 保存要求された設定を記録します。
    ///
    /// 責務: 1件のデフォルト設定をテストから観測可能な状態へ保持します。
    /// - Parameter preference: 保存要求された設定。
    func save(_ preference: DefaultAdapterPreference) {
        savedPreference = preference
    }
}
