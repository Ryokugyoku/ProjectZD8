/// アカウント削除画面が区別して表示する失敗です。
enum AccountDeletionFailure: Equatable {
    /// 保存済みログイン識別子を削除できませんでした。
    case credentialRemovalFailed
}
