import Foundation

/// `UserDefaults` を使って記録開始方法の選択画面の表示済みフラグを端末ローカルに保持します(iCloudへは同期しません)。
@MainActor
final class UserDefaultsAutomaticRecordingChoicePromptCompletionStore: AutomaticRecordingChoicePromptCompletionPort {
    /// フラグを保存する `UserDefaults` です。
    private let defaults: UserDefaults
    /// フラグを識別するキーです。
    private let key: String

    /// 保存先とキーを注入してストアを生成します。
    ///
    /// 責務: 表示済みフラグの保存先を1件の `UserDefaults` キーへ固定します。
    /// - Parameters:
    ///   - defaults: フラグを保存する `UserDefaults`。
    ///   - key: フラグを識別するキー。
    init(
        defaults: UserDefaults = .standard,
        key: String = "deviceConnection.automaticRecordingChoicePromptCompleted"
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// 選択画面を表示済みにしたかどうかを読み込みます。
    ///
    /// 責務: 保存済みの真偽値を返し、未保存または真偽値でない値は未表示として扱います。
    /// - Returns: この端末で選択済みなら `true`。
    func isCompleted() -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }

    /// 選択画面を表示済みとして記録します。
    ///
    /// 責務: 表示済みを表す `true` を置き換えて保存します。
    func markCompleted() {
        defaults.set(true, forKey: key)
    }
}
