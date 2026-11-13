/// デフォルトアダプター設定をプロセス間で保持する保存境界です。
protocol DefaultAdapterPreferencePort {
    /// 現在保存されているデフォルトアダプター設定を読み込みます。
    ///
    /// 責務: 保存済みのデフォルトアダプター設定を1件だけ返します。
    /// - Returns: 復元できた設定。未保存または不完全な場合は `nil`。
    func load() -> DefaultAdapterPreference?

    /// 指定されたデフォルトアダプター設定を保存します。
    ///
    /// 責務: 1件のデフォルトアダプター設定を次回起動用に置き換えて保存します。
    /// - Parameter preference: 保存するデフォルトアダプターの識別情報。
    func save(_ preference: DefaultAdapterPreference)
}
