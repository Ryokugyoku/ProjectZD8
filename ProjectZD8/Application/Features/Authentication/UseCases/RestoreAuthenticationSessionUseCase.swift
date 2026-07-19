/// 保存済みAppleセッションを現在の資格状態と照合します。
struct RestoreAuthenticationSessionUseCase {
    /// Apple資格状態を取得する認証境界です。
    private let authorizationPort: any AppleAccountAuthorizationPort

    /// Appleユーザー識別子を保持する安全な保存境界です。
    private let sessionStore: any AuthenticationSessionStorePort

    /// 認証境界とセッション保存境界を注入します。
    ///
    /// 責務: 保存済みセッション復元を1件のApple資格確認境界と安全な保存境界へ結び付けます。
    /// - Parameters:
    ///   - authorizationPort: Apple資格状態を取得する認証境界。
    ///   - sessionStore: Appleユーザー識別子を保持する安全な保存境界。
    init(
        authorizationPort: any AppleAccountAuthorizationPort,
        sessionStore: any AuthenticationSessionStorePort
    ) {
        self.authorizationPort = authorizationPort
        self.sessionStore = sessionStore
    }

    /// 保存済み識別子を照合し、現在も有効なAppleセッションを返します。
    ///
    /// 責務: 保存済みApple識別子を現在有効なアプリ内セッションへ復元します。
    /// - Returns: Appleが現在も許可しているセッション。未保存または無効な場合は `nil`。
    /// - Throws: 保存領域またはApple資格確認を利用できない場合の境界エラー。
    func execute() async throws -> AppleAccountSession? {
        guard let userIdentifier = try sessionStore.loadUserIdentifier() else {
            return nil
        }

        switch try await authorizationPort.credentialState(for: userIdentifier) {
        case .authorized:
            return AppleAccountSession(userIdentifier: userIdentifier)
        case .revoked, .notFound:
            try sessionStore.removeUserIdentifier()
            return nil
        case .transferred:
            return nil
        }
    }
}
