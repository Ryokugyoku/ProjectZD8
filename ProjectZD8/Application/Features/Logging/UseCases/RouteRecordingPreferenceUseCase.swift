/// 走行ルート(位置)を記録するかどうかの設定を読み書きします。
struct RouteRecordingPreferenceUseCase {
    /// 記録設定の保存境界です。
    private let preferencePort: any RouteRecordingPreferencePort

    /// 保存境界を注入して生成します。
    ///
    /// 責務: 記録設定の読み書きを1件の保存境界へ結び付けます。
    /// - Parameter preferencePort: 記録設定の保存境界。
    init(preferencePort: any RouteRecordingPreferencePort) {
        self.preferencePort = preferencePort
    }

    /// 現在の記録設定を返します。
    ///
    /// 責務: 記録設定の読込を保存境界へ委譲します。
    /// - Returns: 記録が有効なら `true`。
    func load() -> Bool {
        preferencePort.load()
    }

    /// 記録設定を保存します。
    ///
    /// 責務: 1件の記録設定の保存を保存境界へ委譲します。
    /// - Parameter isEnabled: 記録を有効にする場合は `true`。
    func save(_ isEnabled: Bool) {
        preferencePort.save(isEnabled)
    }
}
