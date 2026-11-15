/// 自動記録設定と記録開始方法の選択画面から通知する操作です。
enum AutomaticRecordingPreferenceAction: Equatable, Sendable {
    /// サインイン状態の変化を通知します。
    case signInStateChanged(isSignedIn: Bool)
    /// 設定画面で選択肢が選ばれたことを通知します。
    case settingsChoiceSelected(AutomaticRecordingChoice)
    /// 初回の選択画面で選択肢が選ばれたことを通知します。
    case promptChoiceSelected(AutomaticRecordingChoice)
}
