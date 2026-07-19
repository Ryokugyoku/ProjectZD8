/// アカウント設定モデルへ通知するスコープおよび選択操作です。
enum AccountSettingsAction: Equatable {
    /// 現在認証済みのアプリ固有Appleユーザー識別子を通知します。
    case accountIdentifierChanged(String?)

    /// 表示言語の選択変更を通知します。
    case languageSelected(SettingsLanguage)

    /// 外観モードの選択変更を通知します。
    case appearanceSelected(SettingsAppearance)
}
