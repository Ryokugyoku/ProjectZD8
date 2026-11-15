/// 記録セッション終了後の後処理を1回実行した結果です。
///
/// `completed` 以外はすべて未完了で、次回の実行へ持ち越します。
enum PostSessionProcessingOutcome: Equatable, Sendable {
    /// 実行すべきステップがすべて成功しました。設定によりアップロードを省いた場合も含みます。
    case completed
    /// 記録中のため、残りのステップを呼ばずに持ち越しました。
    case deferredForActiveRecording
    /// アカウントを解決できないため、どのステップも呼ばずに持ち越しました。
    case deferredForUnavailableAccount
    /// 実行期限切れ(キャンセル)のため、残りのステップを呼ばずに中断しました。
    case interruptedByExpiration
    /// 1つ以上のステップが失敗しました。失敗していないステップは実行済みです。
    case stepsFailed(Set<PostSessionProcessingStep>)
}
