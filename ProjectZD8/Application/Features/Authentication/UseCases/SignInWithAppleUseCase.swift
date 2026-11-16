/// Apple認証を実行して有効なセッション識別子を安全に保存します。
struct SignInWithAppleUseCase {
    /// Appleシステム認証を実行する境界です。
    private let authorizationPort: any AppleAccountAuthorizationPort

    /// Appleユーザー識別子を保持する安全な保存境界です。
    private let sessionStore: any AuthenticationSessionStorePort

    /// 過去の削除済みの印を解除する境界です。対話的なサインインでだけ使います。未設定なら解除しません。
    private let deletionMarker: (any AccountDeletionMarkerPort)?

    /// 認証境界とセッション保存境界を注入します。
    ///
    /// 責務: Appleログインを1件のシステム認証境界と安全な保存境界へ結び付けます。
    /// - Parameters:
    ///   - authorizationPort: Appleシステム認証を実行する境界。
    ///   - sessionStore: Appleユーザー識別子を保持する安全な保存境界。
    ///   - deletionMarker: サインイン成功時に過去の削除済みの印を解除する境界。省略時は解除しません。
    init(
        authorizationPort: any AppleAccountAuthorizationPort,
        sessionStore: any AuthenticationSessionStorePort,
        deletionMarker: (any AccountDeletionMarkerPort)? = nil
    ) {
        self.deletionMarker = deletionMarker
        self.authorizationPort = authorizationPort
        self.sessionStore = sessionStore
    }

    /// Apple認証を完了し、返されたユーザー識別子を次回起動用に保存します。
    ///
    /// 責務: 1回のAppleログイン結果を認証済みセッションとして確定します。過去の削除済みの印を先に解除し、解除できなければサインインを失敗にします。
    /// - Returns: Appleが発行したアプリ固有セッション。
    /// - Throws: Apple認証または削除済みの印の解除または安全なセッション保存を完了できない場合の境界エラー。
    func execute() async throws -> AppleAccountSession {
        let session = try await authorizationPort.authorize()
        guard !session.userIdentifier.isEmpty else {
            throw AppleAccountAuthorizationError.failed
        }
        try await deletionMarker?.clearMarker(session.userIdentifier)
        try sessionStore.saveUserIdentifier(session.userIdentifier)
        return session
    }
}
