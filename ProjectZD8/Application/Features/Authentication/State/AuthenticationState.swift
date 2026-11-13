/// 認証入口とルート画面が描画するApplication状態です。
struct AuthenticationState: Equatable {
    /// 現在の認証進行段階です。
    var phase: AuthenticationPhase

    /// 設定などのアカウントスコープへ渡す現在の認証済みセッションです。
    var session: AppleAccountSession?

    /// 免責事項の確認画面を表示するかどうかです。
    var isDisclaimerPresented: Bool

    /// ユーザーへ再試行を案内する直近の失敗です。
    var failure: AuthenticationFailure?

    /// アカウント削除確認と実行の現在段階です。
    var accountDeletionPhase: AccountDeletionPhase

    /// アカウント削除を完了できなかった直近の理由です。
    var accountDeletionFailure: AccountDeletionFailure?

    /// 認証入口の初期状態を生成します。
    ///
    /// 責務: 認証入口の進行段階と対応するAppleセッションを一貫した初期状態へ設定します。
    /// - Parameters:
    ///   - phase: 初期の認証進行段階。
    ///   - session: 初期状態で認証済みとするAppleセッション。
    ///   - isDisclaimerPresented: 初期表示で免責事項を提示するかどうか。
    ///   - failure: 初期表示で案内する認証失敗。
    ///   - accountDeletionPhase: アカウント削除確認の初期段階。
    ///   - accountDeletionFailure: 初期表示で案内する削除失敗。
    init(
        phase: AuthenticationPhase = .checkingSession,
        session: AppleAccountSession? = nil,
        isDisclaimerPresented: Bool = false,
        failure: AuthenticationFailure? = nil,
        accountDeletionPhase: AccountDeletionPhase = .idle,
        accountDeletionFailure: AccountDeletionFailure? = nil
    ) {
        self.phase = phase
        self.session = session
        self.isDisclaimerPresented = isDisclaimerPresented
        self.failure = failure
        self.accountDeletionPhase = accountDeletionPhase
        self.accountDeletionFailure = accountDeletionFailure
    }
}
