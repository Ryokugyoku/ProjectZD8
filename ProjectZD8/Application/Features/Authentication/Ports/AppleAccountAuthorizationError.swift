/// Appleアカウント認証境界が返す区別可能な失敗です。
enum AppleAccountAuthorizationError: Error, Equatable {
    /// ユーザーがシステム認証をキャンセルしました。
    case cancelled

    /// 認証UIまたはApple認証サービスを利用できません。
    case unavailable

    /// Apple認証がその他の理由で失敗しました。
    case failed
}
