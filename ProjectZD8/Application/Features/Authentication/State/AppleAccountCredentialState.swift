/// 保存済みAppleユーザー識別子に対する現在の資格状態です。
enum AppleAccountCredentialState: Equatable, Sendable {
    /// Appleが現在もアプリの利用を許可しています。
    case authorized

    /// ユーザーがアプリへのApple認証許可を取り消しています。
    case revoked

    /// Apple側に対応する資格情報がありません。
    case notFound

    /// アプリ移管に伴うユーザー識別子移行が必要です。
    case transferred
}
