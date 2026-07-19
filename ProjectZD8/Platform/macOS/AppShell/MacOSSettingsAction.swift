#if os(macOS)
/// macOS設定画面からAppShellへ通知する表示設定操作です。
enum MacOSSettingsAction: Equatable {
    /// 表示言語の選択変更を通知します。
    case languageSelected(MacOSSettingsLanguage)

    /// 外観モードの選択変更を通知します。
    case appearanceSelected(MacOSSettingsAppearance)
}
#endif
