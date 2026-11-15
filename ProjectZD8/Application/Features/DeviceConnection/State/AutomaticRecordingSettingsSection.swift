/// 設定画面の「車両検知時の記録開始」区画に表示する内容です。
struct AutomaticRecordingSettingsSection: Equatable, Sendable {
    /// 区画の種別を短く示すローカライズキーです。
    static let eyebrowKey = "settings.automatic_recording.eyebrow"
    /// 区画の見出しを表すローカライズキーです。
    static let titleKey = "settings.automatic_recording.title"
    /// 区画の目的を補足するローカライズキーです。
    static let descriptionKey = "settings.automatic_recording.description"
    /// アプリスイッチャーで終了すると自動検知が止まることを常に案内するローカライズキーです。
    static let terminationNoticeKey = "settings.automatic_recording.termination_notice"

    /// 現在保存されている選択肢です。
    let selectedChoice: AutomaticRecordingChoice

    /// 表示順に並べた選択肢です。
    var choices: [AutomaticRecordingChoice] { AutomaticRecordingChoice.allCases }

    /// 保存済みの自動記録設定から区画内容を生成します。
    ///
    /// 責務: 自動記録設定の真偽値を現在の選択肢を持つ表示内容へ変換します。
    /// - Parameter isAutomaticRecordingEnabled: 自動記録が有効なら `true`。
    init(isAutomaticRecordingEnabled: Bool) {
        selectedChoice = AutomaticRecordingChoice(isAutomaticRecordingEnabled: isAutomaticRecordingEnabled)
    }

    /// 指定した選択肢が現在の保存値かどうかを返します。
    ///
    /// 責務: 1件の選択肢を選択状態の表示可否へ変換します。
    /// - Parameter choice: 判定する選択肢。
    /// - Returns: 保存値と一致する場合は `true`。
    func isSelected(_ choice: AutomaticRecordingChoice) -> Bool {
        choice == selectedChoice
    }
}
