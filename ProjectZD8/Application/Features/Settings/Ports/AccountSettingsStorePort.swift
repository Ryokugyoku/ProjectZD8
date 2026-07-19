/// Connectionを除くアカウント設定の保存と端末間変更通知を抽象化します。
@MainActor
protocol AccountSettingsStorePort: AnyObject {
    /// 指定アカウントの保存済み設定を読み込みます。
    ///
    /// 責務: 1件のアカウント識別子に対応する最新設定を復元します。
    /// - Parameter accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    /// - Returns: 復元できた設定。未保存または不完全な場合は `nil`。
    func load(for accountIdentifier: String) -> AccountSettings?

    /// 指定アカウントの設定を次回起動および端末間同期用に保存します。
    ///
    /// 責務: 1件のアカウント設定をローカル保持と同期保存へ渡します。
    /// - Parameters:
    ///   - settings: Connectionを含まない保存対象設定。
    ///   - accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    func save(_ settings: AccountSettings, for accountIdentifier: String)

    /// 指定アカウントへ外部から届く設定変更の監視を開始します。
    ///
    /// 責務: 1件のアカウントスコープで端末間設定変更だけを購読します。
    /// - Parameters:
    ///   - accountIdentifier: Appleがアプリへ割り当てた空でないユーザー識別子。
    ///   - receive: 同期先から有効な設定が届いたときに呼び出す処理。
    func startObserving(
        for accountIdentifier: String,
        receive: @escaping (AccountSettings) -> Void
    )

    /// 現在のアカウント設定監視を終了します。
    ///
    /// 責務: 以前のアカウントスコープから届く変更通知を停止します。
    func stopObserving()
}
