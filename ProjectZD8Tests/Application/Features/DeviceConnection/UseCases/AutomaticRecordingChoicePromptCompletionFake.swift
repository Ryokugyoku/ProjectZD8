@testable import ProjectZD8

/// 選択画面の表示済みフラグの保存境界の fake です。テストが初期値を決め、表示済みへの記録回数を数えます。
@MainActor
final class AutomaticRecordingChoicePromptCompletionFake: AutomaticRecordingChoicePromptCompletionPort {
    /// 現在保存されている表示済みフラグです。
    private(set) var isCompletedValue: Bool
    /// `markCompleted()` が呼ばれた回数です。
    private(set) var markCount = 0

    /// 初期値を指定して生成します。
    ///
    /// 責務: テスト開始時の表示済みフラグを固定します。
    /// - Parameter isCompleted: 初期値。
    init(isCompleted: Bool) {
        isCompletedValue = isCompleted
    }

    /// 現在のフラグを返します。
    ///
    /// 責務: 保存中の表示済みフラグを返します。
    /// - Returns: 表示済みなら `true`。
    func isCompleted() -> Bool {
        isCompletedValue
    }

    /// 表示済みとして記録します。
    ///
    /// 責務: 記録回数を数え、フラグを `true` に置き換えます。
    func markCompleted() {
        markCount += 1
        isCompletedValue = true
    }
}
