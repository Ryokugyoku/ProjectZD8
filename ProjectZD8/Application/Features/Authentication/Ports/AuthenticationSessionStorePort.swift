/// Appleアカウントセッション識別子の安全な保存を抽象化します。
protocol AuthenticationSessionStorePort {
    /// 保存済みのAppleユーザー識別子を読み込みます。
    ///
    /// 責務: 現在保存されている認証セッション識別子を1件復元します。
    /// - Returns: 保存済み識別子。未保存の場合は `nil`。
    /// - Throws: 安全な保存領域を読み込めない場合は `AuthenticationSessionStoreError`。
    func loadUserIdentifier() throws -> String?

    /// Appleユーザー識別子を安全な保存領域へ置き換え保存します。
    ///
    /// 責務: 1件の認証セッション識別子を次回起動用に保存します。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てた空でないユーザー識別子。
    /// - Throws: 安全な保存領域へ書き込めない場合は `AuthenticationSessionStoreError`。
    func saveUserIdentifier(_ userIdentifier: String) throws

    /// 保存済みAppleユーザー識別子を削除します。
    ///
    /// 責務: 無効になった認証セッション識別子を安全な保存領域から除去します。
    /// - Throws: 安全な保存領域から削除できない場合は `AuthenticationSessionStoreError`。
    func removeUserIdentifier() throws
}
