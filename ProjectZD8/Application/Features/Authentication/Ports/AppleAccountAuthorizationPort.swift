/// Appleアカウントの認証と資格状態確認を抽象化します。
@MainActor
protocol AppleAccountAuthorizationPort {
    /// Appleのシステム認証を実行してアプリ固有セッションを返します。
    ///
    /// 責務: 1回のAppleアカウント認証要求をシステム認証境界へ渡します。
    /// - Returns: Appleが発行したアプリ固有ユーザー識別子を持つセッション。
    /// - Throws: キャンセルまたは認証を完了できない場合は `AppleAccountAuthorizationError`。
    func authorize() async throws -> AppleAccountSession

    /// 保存済みAppleユーザー識別子の現在の資格状態を取得します。
    ///
    /// 責務: 1件のAppleユーザー識別子を現在のシステム資格状態へ照合します。
    /// - Parameter userIdentifier: 以前のApple認証で保存したアプリ固有ユーザー識別子。
    /// - Returns: Appleが返した現在の資格状態。
    /// - Throws: 資格状態を取得できない場合は `AppleAccountAuthorizationError`。
    func credentialState(for userIdentifier: String) async throws -> AppleAccountCredentialState
}
