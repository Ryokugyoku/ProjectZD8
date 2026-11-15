/// 自動記録設定と記録開始方法の選択画面に関する表示状態です。
struct AutomaticRecordingPreferenceState: Equatable, Sendable {
    /// 保存済みの自動記録設定です。
    var isAutomaticRecordingEnabled = false
    /// この端末で選択画面を表示済みにしたかどうかです。
    var isChoicePromptCompleted = false
    /// 有効なアカウントでサインイン済みかどうかです。
    var isSignedIn = false

    /// 設定画面の「車両検知時の記録開始」区画に表示する内容です。
    var settingsSection: AutomaticRecordingSettingsSection {
        AutomaticRecordingSettingsSection(isAutomaticRecordingEnabled: isAutomaticRecordingEnabled)
    }

    /// 記録開始方法の選択画面を表示するかどうかです。
    var isChoicePromptPresented: Bool {
        AutomaticRecordingChoicePromptPolicy.shouldPresent(
            isSignedIn: isSignedIn,
            isPromptCompleted: isChoicePromptCompleted
        )
    }
}
