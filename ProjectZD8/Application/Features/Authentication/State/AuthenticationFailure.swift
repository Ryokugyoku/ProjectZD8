/// ログイン画面で区別して案内する認証失敗です。
enum AuthenticationFailure: Equatable {
    /// 他端末からのログアウトを安全な保存領域へ確定できませんでした。
    case remoteLogoutPersistenceFailed

    /// 保存済みセッションの確認を完了できませんでした。
    case sessionCheckFailed

    /// Apple認証サービスを現在利用できません。
    case serviceUnavailable

    /// Apple認証を完了できませんでした。
    case signInFailed
}
