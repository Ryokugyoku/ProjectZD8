/// 他端末から失効されたアカウントのローカル保存内容を消去します。
@MainActor
struct RemoteAccountLogoutUseCase {
    /// アカウントに属するローカル設定を消去する境界です。
    private let dataEraser: any AccountDataErasurePort

    /// 端末内のログイン識別子を削除する安全な保存境界です。
    private let sessionStore: any AuthenticationSessionStorePort

    /// データ消去境界と認証セッション保存境界を注入します。
    ///
    /// 責務: 他端末から受信した失効をローカルデータと認証識別子の削除へ結び付けます。
    /// - Parameters:
    ///   - dataEraser: アカウントに属する端末内データの消去境界。
    ///   - sessionStore: 保存済みAppleユーザー識別子の削除境界。
    init(
        dataEraser: any AccountDataErasurePort,
        sessionStore: any AuthenticationSessionStorePort
    ) {
        self.dataEraser = dataEraser
        self.sessionStore = sessionStore
    }

    /// 指定アカウントの端末内データを消去してログイン識別子を削除します。
    ///
    /// 責務: 1件の遠隔失効を現在端末の再起動後も維持されるログアウトへ変換します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    /// - Throws: ログイン識別子を安全な保存領域から削除できない場合は `AuthenticationSessionStoreError`。
    func execute(userIdentifier: String) throws {
        dataEraser.eraseAllData(for: userIdentifier)
        try sessionStore.removeUserIdentifier()
    }
}
