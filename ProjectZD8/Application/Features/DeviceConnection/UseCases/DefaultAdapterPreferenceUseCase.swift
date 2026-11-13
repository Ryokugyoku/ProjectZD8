/// デフォルトアダプター設定の保存、復元、検出候補との照合を提供します。
struct DefaultAdapterPreferenceUseCase {
    /// デフォルト設定を保持する保存境界です。
    private let preferencePort: any DefaultAdapterPreferencePort

    /// 保存境界を注入してデフォルト設定ユースケースを生成します。
    ///
    /// 責務: デフォルトアダプター設定のライフサイクルを1件の保存境界へ結び付けます。
    /// - Parameter preferencePort: デフォルト設定を保持する保存境界。
    init(preferencePort: any DefaultAdapterPreferencePort) {
        self.preferencePort = preferencePort
    }

    /// 現在保存されているデフォルトアダプター設定を返します。
    ///
    /// 責務: デフォルト設定の読込を保存境界へ委譲します。
    /// - Returns: 復元できた設定。未保存または不完全な場合は `nil`。
    func load() -> DefaultAdapterPreference? {
        preferencePort.load()
    }

    /// 検出済み候補を次回起動用のデフォルト設定として保存します。
    ///
    /// 責務: 1件の検出済み候補をデフォルト設定へ変換して保存境界へ渡します。
    /// - Parameter adapter: ユーザーがデフォルトとして確定した候補。
    /// - Returns: 保存境界へ渡したデフォルト設定。
    @discardableResult
    func save(adapter: DiscoveredAdapter) -> DefaultAdapterPreference {
        let preference = DefaultAdapterPreference(adapter: adapter)
        preferencePort.save(preference)
        return preference
    }

    /// 保存済みデフォルトと一致する検出候補を返します。
    ///
    /// 責務: 1件のデフォルト設定を最新の検出候補一覧と照合します。
    /// - Parameters:
    ///   - preference: 照合する保存済みデフォルト設定。
    ///   - adapters: 最新探索で検出した候補一覧。
    /// - Returns: 保存済み識別情報と一致する候補。存在しない場合は `nil`。
    func detectedAdapter(
        matching preference: DefaultAdapterPreference,
        in adapters: [DiscoveredAdapter]
    ) -> DiscoveredAdapter? {
        adapters.first(where: preference.matches)
    }
}
