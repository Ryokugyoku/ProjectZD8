/// Connectionを除くアカウント設定の保存、復元、同期監視を調整します。
@MainActor
final class AccountSettingsUseCase {
    /// アカウント設定を保持する保存境界です。
    private let store: any AccountSettingsStorePort

    /// 保存境界を注入してユースケースを生成します。
    ///
    /// 責務: アカウント設定のライフサイクルを1件の保存境界へ結び付けます。
    /// - Parameter store: ローカル保持と端末間同期を提供する保存境界。
    init(store: any AccountSettingsStorePort) {
        self.store = store
    }

    /// 指定アカウントの保存済み設定または既定値を返します。
    ///
    /// 責務: 1件のアカウント設定を保存境界から復元可能な表示初期値へ変換します。
    /// - Parameter accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    /// - Returns: 保存済み設定。未保存の場合は既定設定。
    func load(for accountIdentifier: String) -> AccountSettings {
        store.load(for: accountIdentifier) ?? AccountSettings()
    }

    /// 指定アカウントの設定を保存します。
    ///
    /// 責務: Connectionを含まない1件の設定をアカウント保存境界へ渡します。
    /// - Parameters:
    ///   - settings: 保存する言語と外観。
    ///   - accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    func save(_ settings: AccountSettings, for accountIdentifier: String) {
        store.save(settings, for: accountIdentifier)
    }

    /// 指定アカウントの端末間設定変更を購読します。
    ///
    /// 責務: 1件のアカウントスコープの同期変更を呼出元へ中継します。
    /// - Parameters:
    ///   - accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    ///   - receive: 有効な同期設定を受け取る処理。
    func startObserving(
        for accountIdentifier: String,
        receive: @escaping (AccountSettings) -> Void
    ) {
        store.startObserving(for: accountIdentifier, receive: receive)
    }

    /// 現在の端末間設定変更購読を終了します。
    ///
    /// 責務: 保存境界が保持する以前のアカウント監視を停止します。
    func stopObserving() {
        store.stopObserving()
    }
}
