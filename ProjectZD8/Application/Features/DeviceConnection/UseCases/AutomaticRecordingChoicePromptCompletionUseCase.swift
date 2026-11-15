/// 記録開始方法の選択画面をこの端末で表示済みにしたかどうかを読み書きします。
struct AutomaticRecordingChoicePromptCompletionUseCase {
    /// 表示済みフラグの保存境界です。
    private let completionPort: any AutomaticRecordingChoicePromptCompletionPort

    /// 保存境界を注入して生成します。
    ///
    /// 責務: 表示済みフラグの読み書きを1件の保存境界へ結び付けます。
    /// - Parameter completionPort: 表示済みフラグの保存境界。
    init(completionPort: any AutomaticRecordingChoicePromptCompletionPort) {
        self.completionPort = completionPort
    }

    /// 選択画面を表示済みにしたかどうかを返します。
    ///
    /// 責務: 表示済みフラグの読込を保存境界へ委譲します。
    /// - Returns: この端末で選択済みなら `true`。
    func isCompleted() -> Bool {
        completionPort.isCompleted()
    }

    /// 選択画面を表示済みとして記録します。
    ///
    /// 責務: 表示済みフラグの保存を保存境界へ委譲します。
    func markCompleted() {
        completionPort.markCompleted()
    }
}
