/// アカウント削除画面が区別して表示する失敗です。
enum AccountDeletionFailure: Equatable {
    /// CloudKit、ローカルデータ、または保存済みログイン識別子を完全に削除できませんでした。
    case deletionFailed
}
