/// 起動時のサインイン確認が「確認できなかった」(照会の失敗)時に、時間をおいて再確認する判定です。SwiftUIに依存しない純粋型です。
///
/// 「本当に未サインイン/失効」(照会の結果が `nil`)は再確認しません。確認できていない資格を暫定的に信用しないため、
/// 再確認の間もサインアウトとして扱い、再確認の成功で初めてサインイン済みに進みます。
///
/// 既定値の根拠: オフライン直後や端末ロック解除直後の Keychain 読み出し不可は数秒〜数十秒で解けることが多いため、
/// 5秒・15秒・60秒と間を広げ、以後は60秒ごとに、合計10回(約8分)で打ち切ります。次の前面復帰で回数を取り直します。
nonisolated struct AuthenticationSessionRecheckPolicy: Equatable, Sendable {
    /// 既定の判定です(5秒、15秒、60秒、以後60秒ごと、合計10回)。
    static let standard = AuthenticationSessionRecheckPolicy(
        leadingDelays: [.seconds(5), .seconds(15), .seconds(60)],
        repeatingDelay: .seconds(60),
        maximumAttempts: 10
    )

    /// 最初の数回の待ち時間です(1回目の前、2回目の前、…の順)。
    let leadingDelays: [Duration]
    /// `leadingDelays` を使い切った後の待ち時間です。
    let repeatingDelay: Duration
    /// 時間経過による再確認の上限回数です。
    let maximumAttempts: Int

    /// 待ち時間と上限回数を固定して生成します。
    ///
    /// 責務: 負の待ち時間を0へ、負の上限回数を0(再確認しない)へ丸めて保持します。
    /// - Parameters:
    ///   - leadingDelays: 最初の数回の待ち時間。
    ///   - repeatingDelay: 以後の待ち時間。
    ///   - maximumAttempts: 時間経過による再確認の上限回数。
    init(leadingDelays: [Duration], repeatingDelay: Duration, maximumAttempts: Int) {
        self.leadingDelays = leadingDelays.map { max(.zero, $0) }
        self.repeatingDelay = max(.zero, repeatingDelay)
        self.maximumAttempts = max(0, maximumAttempts)
    }

    /// 指定回目の再確認の前に待つ時間を返します。
    ///
    /// 責務: 0始まりの回数を待ち時間へ変換し、上限に達していれば `nil` を返します。
    /// - Parameter attempt: これから行う再確認の回数(0始まり。前面復帰で0へ戻します)。
    /// - Returns: 待ち時間。負の回数・上限以上なら `nil`(再確認しない)。
    func delay(beforeAttempt attempt: Int) -> Duration? {
        guard attempt >= 0, attempt < maximumAttempts else { return nil }
        return attempt < leadingDelays.count ? leadingDelays[attempt] : repeatingDelay
    }

    /// いま再確認すべき状態かどうかを返します。
    ///
    /// 責務: サインアウト表示中で、直近の確認が照会の失敗のまま解決していない時だけ再確認を許します。
    /// 手動サインインの最中・サインイン済み・確認中は再確認しません。
    /// - Parameters:
    ///   - phase: 現在の認証段階。
    ///   - isSessionCheckUnresolved: 直近のサインイン確認が照会の失敗のまま解決していないかどうか。
    /// - Returns: 再確認すべきなら `true`。
    func shouldRecheck(phase: AuthenticationPhase, isSessionCheckUnresolved: Bool) -> Bool {
        switch phase {
        case .signedOut: isSessionCheckUnresolved
        case .checkingSession, .signingIn, .signedIn, .deletingAccount: false
        }
    }
}
