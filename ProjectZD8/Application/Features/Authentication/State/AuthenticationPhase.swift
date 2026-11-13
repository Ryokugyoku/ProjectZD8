/// アプリの認証入口が取り得る進行段階です。
enum AuthenticationPhase: Equatable {
    /// 保存済みセッションの資格状態を確認しています。
    case checkingSession

    /// Appleアカウントでのログイン操作を待っています。
    case signedOut

    /// Appleの認証結果を待っています。
    case signingIn

    /// 有効なAppleアカウントセッションが確認されています。
    case signedIn
}
