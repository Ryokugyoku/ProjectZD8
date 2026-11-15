/// 記録開始方法の選択画面を表示するかどうかを判定します。
enum AutomaticRecordingChoicePromptPolicy {
    /// 選択画面を表示するかどうかを返します。
    ///
    /// 責務: サインイン状態と端末ローカルの表示済みフラグを1件の表示可否へ変換します。
    /// - Parameters:
    ///   - isSignedIn: 有効なアカウントでサインイン済みかどうか。
    ///   - isPromptCompleted: この端末で選択画面を表示済みにしたかどうか。
    /// - Returns: サインイン済みかつ未表示の場合だけ `true`。
    static func shouldPresent(isSignedIn: Bool, isPromptCompleted: Bool) -> Bool {
        isSignedIn && !isPromptCompleted
    }
}
