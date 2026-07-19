/// Appleアカウント認証から得たアプリ固有セッション識別情報です。
struct AppleAccountSession: Equatable, Sendable {
    /// Appleがこのアプリへ割り当てた安定ユーザー識別子です。
    let userIdentifier: String

    /// 検証済みのAppleユーザー識別子からセッションを生成します。
    ///
    /// 責務: Appleユーザー識別子をアプリ内セッション表現へ固定します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    init(userIdentifier: String) {
        self.userIdentifier = userIdentifier
    }
}
