/// 初回サインイン直後に表示する記録開始方法の選択画面の文言キーです。
enum AutomaticRecordingChoicePromptContent {
    /// 画面の見出しを表すローカライズキーです。
    static let titleKey = "automatic_recording.prompt.title"
    /// 画面の目的と後から変更できることを説明するローカライズキーです。
    static let messageKey = "automatic_recording.prompt.message"
    /// 表示順に並べた選択肢です。
    static let choices = AutomaticRecordingChoice.allCases
}
