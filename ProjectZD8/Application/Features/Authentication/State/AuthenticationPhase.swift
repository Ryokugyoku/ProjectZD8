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

    /// アカウント削除の実行中です。同期・保存・記録・自動アップロードは止まり、削除の進み具合を示す画面を表示し続けます。
    case deletingAccount
}

extension AuthenticationPhase {
    /// 認証済みアカウント用の画面(進行中の削除の進み具合を含む)を表示すべき段階かどうかです。
    ///
    /// 責務: 削除中にログイン画面へ切り替わって進み具合の画面が消えないよう、画面の出し分けを段階から決めます。
    var showsAuthenticatedShell: Bool {
        switch self {
        case .signedIn, .deletingAccount: true
        case .checkingSession, .signedOut, .signingIn: false
        }
    }
}
