/// 認証状態の変化から、常駐リンク監視と記録側へ何を伝えるかを決めます。SwiftUI・デバイスAPIに依存しない純粋型です。
///
/// `IOSAdapterLinkSupervisionDriver` が観測した認証状態をこの型へ渡し、返った指示だけを監視と記録側へ写します。
/// 確認できていない資格(サインイン確認の照会の失敗)はサインアウトとして扱い、サインイン済みとは伝えません。
nonisolated struct AdapterLinkSupervisionAuthenticationRelay: Sendable {
    /// 1回の認証状態の反映で行う指示です。
    struct Instruction: Equatable, Sendable {
        /// 記録側へ伝えるアカウント識別子です。変化が無ければ `nil`(伝えない)。
        let accountIdentifierChange: AccountIdentifierChange?
        /// 監視へ伝えるサインイン有無です。段階が変わらなければ `nil`(伝えない)。
        let isSignedIn: Bool?
        /// 既定アダプター設定を監視に読み直させるかどうかです(サインアウトで設定が消えている場合があるため)。
        let reloadsDefaultAdapterPreference: Bool
    }

    /// 記録側へ伝えるアカウント識別子の変化です。
    struct AccountIdentifierChange: Equatable, Sendable {
        /// 新しいアカウント識別子です。サインアウトでは `nil` です。
        let accountIdentifier: String?
    }

    /// 最後に伝えた認証段階です。まだ伝えていなければ `nil` です。
    private(set) var lastPhase: AuthenticationPhase?
    /// 最後に伝えたアカウント識別子です。
    private(set) var lastAccountIdentifier: String?

    /// まだ何も伝えていない状態で生成します。
    ///
    /// 責務: 最初の反映で必ず段階を伝えるよう、伝えた記録を空にします。
    init() {}

    /// 認証状態を反映し、伝える指示を返します。
    ///
    /// 責務: サインイン済みなら識別子を、サインアウトとアカウント削除中なら `nil` を、確認中・サインイン中なら前の識別子を保ち、変化した時だけ伝えます。
    /// 段階が変わった時だけサインイン有無を伝え、サインアウトへ変わった時は既定アダプター設定を読み直させます。
    /// - Parameters:
    ///   - phase: 現在の認証段階。
    ///   - userIdentifier: 現在のセッションのアカウント識別子。セッションが無ければ `nil`。
    /// - Returns: 監視と記録側へ伝える指示。
    mutating func apply(phase: AuthenticationPhase, userIdentifier: String?) -> Instruction {
        let accountIdentifier: String? = switch phase {
        case .signedIn: userIdentifier
        case .signedOut, .deletingAccount: nil
        case .checkingSession, .signingIn: lastAccountIdentifier
        }
        var accountIdentifierChange: AccountIdentifierChange?
        if accountIdentifier != lastAccountIdentifier {
            lastAccountIdentifier = accountIdentifier
            accountIdentifierChange = AccountIdentifierChange(accountIdentifier: accountIdentifier)
        }
        guard !Self.isSame(phase, as: lastPhase) else {
            return Instruction(accountIdentifierChange: accountIdentifierChange, isSignedIn: nil, reloadsDefaultAdapterPreference: false)
        }
        lastPhase = phase
        return Instruction(
            accountIdentifierChange: accountIdentifierChange,
            isSignedIn: Self.isSignedIn(phase),
            reloadsDefaultAdapterPreference: Self.isSignedOut(phase)
        )
    }

    /// 2つの段階が同じかどうかを返します。
    ///
    /// 責務: 前回の段階が無ければ異なるものとして扱います。
    /// - Parameters:
    ///   - phase: 現在の段階。
    ///   - previous: 前回伝えた段階。
    /// - Returns: 同じ段階なら `true`。
    private static func isSame(_ phase: AuthenticationPhase, as previous: AuthenticationPhase?) -> Bool {
        switch (phase, previous) {
        case (.checkingSession, .checkingSession?),
             (.signedOut, .signedOut?),
             (.signingIn, .signingIn?),
             (.signedIn, .signedIn?),
             (.deletingAccount, .deletingAccount?):
            true
        default:
            false
        }
    }

    /// サインイン済みの段階かどうかを返します。
    ///
    /// 責務: 監視へ伝えるサインイン有無を段階から決めます。
    /// - Parameter phase: 認証段階。
    /// - Returns: サインイン済みなら `true`。
    private static func isSignedIn(_ phase: AuthenticationPhase) -> Bool {
        if case .signedIn = phase { return true }
        return false
    }

    /// サインアウトの段階かどうかを返します。
    ///
    /// 責務: 既定アダプター設定を読み直させるかを段階から決めます。
    /// - Parameter phase: 認証段階。
    /// - Returns: サインアウトなら `true`。
    private static func isSignedOut(_ phase: AuthenticationPhase) -> Bool {
        if case .signedOut = phase { return true }
        return false
    }
}
