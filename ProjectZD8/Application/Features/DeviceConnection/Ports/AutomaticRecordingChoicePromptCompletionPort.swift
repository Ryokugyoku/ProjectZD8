/// 記録開始方法の選択画面をこの端末で表示済みにしたかどうかを端末ローカルに保持する保存境界です。
@MainActor
protocol AutomaticRecordingChoicePromptCompletionPort: AnyObject {
    /// 選択画面を表示済みにしたかどうかを読み込みます。
    ///
    /// 責務: 端末ローカルに保存された表示済みフラグを1件返します。
    /// - Returns: この端末で選択済みなら `true`。未保存の場合は `false`。
    func isCompleted() -> Bool

    /// 選択画面を表示済みとして記録します。
    ///
    /// 責務: 表示済みフラグを端末ローカルへ保存し、以後の起動とサインインで選択画面を出さないようにします。
    func markCompleted()
}
