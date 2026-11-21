/// 軌跡の記録をするかどうかを端末ローカルに保持する保存境界です。
@MainActor
protocol RouteRecordingPreferencePort: AnyObject {
    /// 軌跡記録設定を読み込みます。
    ///
    /// 責務: 端末ローカルに保存された軌跡記録設定を1件返します。
    /// - Returns: 記録が有効なら `true`。未保存の場合の既定値は実装が決めます。
    func load() -> Bool

    /// 軌跡記録設定を保存します。
    ///
    /// 責務: 1件の軌跡記録設定を端末ローカルへ置き換えて保存します。
    /// - Parameter isEnabled: 記録を有効にする場合は `true`。
    func save(_ isEnabled: Bool)
}
