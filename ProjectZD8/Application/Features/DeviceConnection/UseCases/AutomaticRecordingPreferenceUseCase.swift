/// 車両検知時に自動で記録を始めるかどうかの設定を読み書きします。
struct AutomaticRecordingPreferenceUseCase {
    /// 自動記録設定の保存境界です。
    private let preferencePort: any AutomaticRecordingPreferencePort

    /// 保存境界を注入して生成します。
    ///
    /// 責務: 自動記録設定の読み書きを1件の保存境界へ結び付けます。
    /// - Parameter preferencePort: 自動記録設定の保存境界。
    init(preferencePort: any AutomaticRecordingPreferencePort) {
        self.preferencePort = preferencePort
    }

    /// 現在の自動記録設定を返します。
    ///
    /// 責務: 自動記録設定の読込を保存境界へ委譲します。
    /// - Returns: 自動記録が有効なら `true`。
    func load() -> Bool {
        preferencePort.load()
    }

    /// 自動記録設定を保存します。
    ///
    /// 責務: 1件の自動記録設定の保存を保存境界へ委譲します。次の車両検知から反映されます。
    /// - Parameter isEnabled: 自動記録を有効にする場合は `true`。
    func save(_ isEnabled: Bool) {
        preferencePort.save(isEnabled)
    }
}
