/// アカウント保存データとログイン識別子を順序付けて削除します。
@MainActor
struct DeleteAccountUseCase {
    /// 他端末へ新しいセッション失効世代を発行する境界です。
    private let sessionRevocation: any AccountSessionRevocationPort

    /// アカウントに属する同期設定と端末設定を消去する境界です。
    private let dataEraser: any AccountDataErasurePort

    /// 最後に削除する保存済みログイン識別子の境界です。
    private let sessionStore: any AuthenticationSessionStorePort

    /// 失効同期、データ消去、認証セッション保存の各境界を注入します。
    ///
    /// 責務: アカウント削除順序を失効発行、データ消去、資格情報削除の3境界へ固定します。
    /// - Parameters:
    ///   - sessionRevocation: 他端末へセッション失効を発行する境界。
    ///   - dataEraser: アカウントに属するアプリ保存データの消去境界。
    ///   - sessionStore: 保存済みAppleユーザー識別子の削除境界。
    init(
        sessionRevocation: any AccountSessionRevocationPort,
        dataEraser: any AccountDataErasurePort,
        sessionStore: any AuthenticationSessionStorePort
    ) {
        self.sessionRevocation = sessionRevocation
        self.dataEraser = dataEraser
        self.sessionStore = sessionStore
    }

    /// 指定アカウントを他端末へ失効通知してからアプリ保存データとログイン識別子を削除します。
    ///
    /// 責務: 1件の認証済みアカウントを再試行可能な順序で端末から削除します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    /// - Throws: ログイン識別子を安全な保存領域から削除できない場合は `AuthenticationSessionStoreError`。
    func execute(userIdentifier: String) throws {
        guard !userIdentifier.isEmpty else {
            throw AuthenticationSessionStoreError.unavailable
        }
        sessionRevocation.publishRevocation(for: userIdentifier)
        dataEraser.eraseAllData(for: userIdentifier)
        try sessionStore.removeUserIdentifier()
    }
}
