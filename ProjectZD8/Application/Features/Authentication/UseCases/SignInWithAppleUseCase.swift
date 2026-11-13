/// Apple認証を実行して有効なセッション識別子を安全に保存します。
struct SignInWithAppleUseCase {
    /// Appleシステム認証を実行する境界です。
    private let authorizationPort: any AppleAccountAuthorizationPort

    /// Appleユーザー識別子を保持する安全な保存境界です。
    private let sessionStore: any AuthenticationSessionStorePort

    /// 認証境界とセッション保存境界を注入します。
    ///
    /// 責務: Appleログインを1件のシステム認証境界と安全な保存境界へ結び付けます。
    /// - Parameters:
    ///   - authorizationPort: Appleシステム認証を実行する境界。
    ///   - sessionStore: Appleユーザー識別子を保持する安全な保存境界。
    init(
        authorizationPort: any AppleAccountAuthorizationPort,
        sessionStore: any AuthenticationSessionStorePort
    ) {
        self.authorizationPort = authorizationPort
        self.sessionStore = sessionStore
    }

    /// Apple認証を完了し、返されたユーザー識別子を次回起動用に保存します。
    ///
    /// 責務: 1回のAppleログイン結果を認証済みセッションとして確定します。
    /// - Returns: Appleが発行したアプリ固有セッション。
    /// - Throws: Apple認証または安全なセッション保存を完了できない場合の境界エラー。
    func execute() async throws -> AppleAccountSession {
        let session = try await authorizationPort.authorize()
        guard !session.userIdentifier.isEmpty else {
            throw AppleAccountAuthorizationError.failed
        }
        try sessionStore.saveUserIdentifier(session.userIdentifier)
        return session
    }
}
