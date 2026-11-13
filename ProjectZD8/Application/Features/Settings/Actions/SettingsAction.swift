/// 設定画面からモデルへ送る操作です。
nonisolated enum SettingsAction: Sendable {
    /// 外観を変更します。
    case appearanceChanged(AppAppearance)
    /// デモモードを切り替えます。
    case demoModeChanged(Bool)
    /// この端末に残すRawの保持期間を変更します。
    case localRawRetentionChanged(LocalRawRetention)
    /// 保存済みの設定を読み直します。
    case reloadRequested
}
