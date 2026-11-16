/// 認証段階の変化から、進行中の取得(記録)をどの理由で終わらせるかを決める純粋な判定です。SwiftUIに依存しません。
///
/// サインアウト(アカウント削除によるサインアウトを含む)では、手動接続で始めた記録も常駐リンクで始めた記録も、
/// ユーザーの[切断](`userDisconnected`)ではなく `accountSignedOut` で終えます(取得記録・終了通知・接続セッションの理由を揃え、
/// 常駐リンク監視がユーザー切断後の保持に入らないようにするため)。確認中・サインイン中・サインイン済みへの変化では終わらせません。
nonisolated struct AuthenticationAcquisitionEndPolicy: Equatable, Sendable {
    /// 判定を生成します。
    ///
    /// 責務: 状態を持たない判定を構築します。
    init() {}

    /// 新しい認証段階へ変わった時に、取得を終わらせる理由を返します。
    ///
    /// 責務: サインアウトへの変化だけを `accountSignedOut` の終了へ変換します。
    /// - Parameter phase: 変化後の認証段階。
    /// - Returns: 取得を終わらせる理由。終わらせない段階なら `nil`。
    func endReason(forChangeTo phase: AuthenticationPhase) -> ConnectionSessionEndReason? {
        switch phase {
        case .signedOut: .accountSignedOut
        case .checkingSession, .signingIn, .signedIn: nil
        }
    }
}
