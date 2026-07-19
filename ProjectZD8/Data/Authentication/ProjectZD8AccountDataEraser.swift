/// ProjectZD8が現在保持する同期設定と端末固有設定を消去します。
@MainActor
final class ProjectZD8AccountDataEraser: AccountDataErasurePort {
    /// iCloud共有設定と同じ設定の端末内コピーを保持する保存先です。
    private let accountSettingsStore: UbiquitousKeyValueStoreAccountSettingsStore

    /// 端末固有のデフォルトアダプター選択を保持する保存先です。
    private let defaultAdapterStore: UserDefaultsDefaultAdapterPreferenceStore

    /// アカウント設定と端末固有設定の具体保存先を注入します。
    ///
    /// 責務: 現在のProjectZD8が永続化する2種類の設定保存先を削除境界へ固定します。
    /// - Parameters:
    ///   - accountSettingsStore: iCloud共有設定と端末内コピーの保存先。
    ///   - defaultAdapterStore: 端末固有のデフォルトアダプター設定保存先。
    init(
        accountSettingsStore: UbiquitousKeyValueStoreAccountSettingsStore,
        defaultAdapterStore: UserDefaultsDefaultAdapterPreferenceStore
    ) {
        self.accountSettingsStore = accountSettingsStore
        self.defaultAdapterStore = defaultAdapterStore
    }

    /// 指定アカウントの共有設定と端末内のアダプター設定を消去します。
    ///
    /// 責務: 現在実装済みの全ProjectZD8設定を1件のアカウント削除要求から除去します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    func eraseAllData(for userIdentifier: String) {
        accountSettingsStore.remove(for: userIdentifier)
        defaultAdapterStore.remove()
    }
}
