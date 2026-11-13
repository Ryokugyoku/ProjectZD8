/// アプリ設定をこの端末に保存する契約です。
nonisolated protocol AppSettingsStorePort: Sendable {
    /// 責務: 保存済みの設定を返します。未保存ならプラットフォームの既定値を返します。
    func load() -> AppSettings
    /// 責務: 設定を保存します。
    func save(_ settings: AppSettings)
}
