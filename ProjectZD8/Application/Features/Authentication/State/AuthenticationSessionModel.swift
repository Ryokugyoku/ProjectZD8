import Observation

/// 認証入口の型付き操作をApplicationユースケースと表示状態へ変換します。
@MainActor
@Observable
final class AuthenticationSessionModel {
    /// ルート画面とログイン画面が描画する現在の認証状態です。
    var state: AuthenticationState

    /// 保存済みセッションをApple資格状態と照合するユースケースです。
    @ObservationIgnored
    private let restoreSession: RestoreAuthenticationSessionUseCase

    /// Apple認証結果を安全なセッションとして保存するユースケースです。
    @ObservationIgnored
    private let signInWithApple: SignInWithAppleUseCase

    /// 認証済みアカウントのアプリ保存データとログイン識別子を削除するユースケースです。
    @ObservationIgnored
    private let deleteAccount: DeleteAccountUseCase

    /// 他端末から受信した失効を端末内ログアウトへ反映するユースケースです。
    @ObservationIgnored
    private let remoteAccountLogout: RemoteAccountLogoutUseCase

    /// アカウント別セッション失効を端末間で監視する境界です。
    @ObservationIgnored
    private let sessionRevocation: any AccountSessionRevocationPort

    /// 重複した起動時確認を防ぐ復元タスクです。
    @ObservationIgnored
    private var restorationTask: Task<Void, Never>?

    /// 重複したApple認証要求を防ぐログインタスクです。
    @ObservationIgnored
    private var signInTask: Task<Void, Never>?

    /// 重複したアカウント削除要求を防ぐ削除タスクです。
    @ObservationIgnored
    private var accountDeletionTask: Task<Void, Never>?

    /// サインイン確認の再確認をすべき状態かの判定です。
    @ObservationIgnored
    private let recheckPolicy: AuthenticationSessionRecheckPolicy

    /// サインイン確認の再確認を待ち時間と上限に沿って実行する列です。
    @ObservationIgnored
    private let recheckScheduler: AuthenticationSessionRecheckScheduler

    /// 直近のサインイン確認が照会の失敗(throw)のまま解決していないかどうかです。手動サインインの開始で解除します。
    @ObservationIgnored
    private var isSessionCheckUnresolved = false

    /// 初期表示状態、認証ユースケース、端末間失効境界を注入します。
    ///
    /// 責務: 認証入口の状態遷移をApple認証と端末間セッション失効のApplication境界へ結び付けます。
    /// - Parameters:
    ///   - state: 認証入口の初期表示状態。
    ///   - restoreSession: 保存済みセッションを照合するユースケース。
    ///   - signInWithApple: Apple認証とセッション保存を行うユースケース。
    ///   - deleteAccount: アカウント保存データとログイン識別子を削除するユースケース。
    ///   - remoteAccountLogout: 他端末から失効されたアカウントを端末内からログアウトするユースケース。
    ///   - sessionRevocation: アカウント別セッション失効の同期境界。
    ///   - recheckPolicy: サインイン確認が照会の失敗だった時の再確認の待ち時間と上限。
    ///   - recheckSleep: 再確認の待機に使う処理。テストは実時間を待たない実装を渡します。
    init(
        state: AuthenticationState,
        restoreSession: RestoreAuthenticationSessionUseCase,
        signInWithApple: SignInWithAppleUseCase,
        deleteAccount: DeleteAccountUseCase,
        remoteAccountLogout: RemoteAccountLogoutUseCase,
        sessionRevocation: any AccountSessionRevocationPort,
        recheckPolicy: AuthenticationSessionRecheckPolicy = .standard,
        recheckSleep: @escaping AuthenticationSessionRecheckScheduler.Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.state = state
        self.recheckPolicy = recheckPolicy
        recheckScheduler = AuthenticationSessionRecheckScheduler(policy: recheckPolicy, sleep: recheckSleep)
        self.restoreSession = restoreSession
        self.signInWithApple = signInWithApple
        self.deleteAccount = deleteAccount
        self.remoteAccountLogout = remoteAccountLogout
        self.sessionRevocation = sessionRevocation

        if state.phase == .signedIn, let userIdentifier = state.session?.userIdentifier {
            sessionRevocation.registerCurrentSession(for: userIdentifier)
            startObservingSessionRevocation(for: userIdentifier)
        }
    }

    /// 認証入口から受け取った1件の操作を表示状態またはユースケースへ反映します。
    ///
    /// 責務: 1件の認証操作を対応するApplication状態遷移へ変換します。
    /// - Parameter action: ログイン画面またはルート画面から通知された型付き操作。
    func send(_ action: AuthenticationAction) {
        switch action {
        case .appeared:
            beginSessionRestorationIfNeeded()
        case .foregroundEntered:
            restartSessionRecheckIfNeeded(immediately: true)
        case .loginTapped:
            presentDisclaimerIfPossible()
        case .disclaimerDismissed:
            state.isDisclaimerPresented = false
        case .disclaimerAccepted:
            beginSignInIfPossible()
        case .retryTapped:
            state.failure = nil
            presentDisclaimerIfPossible()
        case .accountDeletionRequested:
            presentAccountDeletionWarningIfPossible()
        case .accountDeletionWarningConfirmed:
            presentAccountDeletionReviewIfPossible()
        case .accountDeletionCancelled:
            cancelAccountDeletionIfPossible()
        case .accountDeletionConfirmed:
            beginAccountDeletionIfPossible()
        }
    }

    /// 認証済みで削除処理中でない場合に最初の警告を提示します。
    ///
    /// 責務: 設定画面の削除要求を取り消し可能な警告段階へ遷移させます。
    private func presentAccountDeletionWarningIfPossible() {
        guard state.phase == .signedIn,
              state.accountDeletionPhase == .idle else { return }
        state.accountDeletionFailure = nil
        state.accountDeletionPhase = .warning
    }

    /// 最初の警告が表示中の場合だけ削除事項の確認段階へ進めます。
    ///
    /// 責務: 1段階目の警告同意を最終削除事項の表示状態へ変換します。
    private func presentAccountDeletionReviewIfPossible() {
        guard state.phase == .signedIn,
              state.accountDeletionPhase == .warning else { return }
        state.accountDeletionPhase = .reviewing
    }

    /// 削除実行中でない確認状態を通常の認証済み状態へ戻します。
    ///
    /// 責務: 未実行のアカウント削除確認だけを安全に取り消します。
    private func cancelAccountDeletionIfPossible() {
        guard state.accountDeletionPhase != .deleting else { return }
        state.accountDeletionFailure = nil
        state.accountDeletionPhase = .idle
    }

    /// 最終確認済みの認証済みアカウントを1回だけ削除します。
    ///
    /// 責務: 最終削除操作をアカウント削除ユースケースとログイン画面への状態遷移へ結び付けます。
    private func beginAccountDeletionIfPossible() {
        guard
            state.phase == .signedIn,
            state.accountDeletionPhase == .reviewing || state.accountDeletionPhase == .failed,
            let userIdentifier = state.session?.userIdentifier,
            accountDeletionTask == nil
        else { return }

        state.accountDeletionFailure = nil
        state.accountDeletionPhase = .deleting
        accountDeletionTask = Task { [weak self] in
            guard let self else { return }
            defer { accountDeletionTask = nil }
            do {
                try await deleteAccount.execute(userIdentifier: userIdentifier)
                sessionRevocation.stopObserving()
                state.accountDeletionPhase = .idle
                state.accountDeletionFailure = nil
                state.session = nil
                state.phase = .signedOut
            } catch {
                state.accountDeletionFailure = .deletionFailed
                state.accountDeletionPhase = .failed
            }
        }
    }

    /// 初期確認中で未実行の場合に限り保存済みセッションの復元を開始します。
    ///
    /// 責務: 起動中に1回だけセッション復元ユースケースを実行します。
    private func beginSessionRestorationIfNeeded() {
        guard state.phase == .checkingSession, restorationTask == nil else { return }
        restorationTask = Task { [weak self] in
            guard let self else { return }
            defer { restorationTask = nil }
            do {
                applyConfirmedSession(try await restoreSession.execute())
            } catch {
                applyUnconfirmedSessionCheck()
                restartSessionRecheckIfNeeded(immediately: false)
            }
        }
    }

    /// 照会で確かめられたセッションを状態へ反映します。
    ///
    /// 責務: 有効なセッションならサインイン済みにして失効の監視を始め、`nil`(本当に未サインイン/失効)ならエラーなしのサインアウトにします。
    /// どちらも確認は解決したものとして再確認をやめます。
    /// - Parameter session: 照会の結果。
    private func applyConfirmedSession(_ session: AppleAccountSession?) {
        isSessionCheckUnresolved = false
        recheckScheduler.cancel()
        state.session = session
        if state.failure == .sessionCheckFailed {
            state.failure = nil
        }
        guard let userIdentifier = session?.userIdentifier else {
            state.phase = .signedOut
            return
        }
        state.isDisclaimerPresented = false
        state.phase = .signedIn
        startObservingSessionRevocation(for: userIdentifier)
    }

    /// 照会に失敗した(確認できなかった)ことを状態へ反映します。
    ///
    /// 責務: 確認できていない資格を信用せず、ログイン画面と `.sessionCheckFailed` を出し、再確認の対象にします。
    private func applyUnconfirmedSessionCheck() {
        isSessionCheckUnresolved = true
        state.session = nil
        state.phase = .signedOut
        state.failure = .sessionCheckFailed
    }

    /// 再確認すべき状態なら、回数を取り直して再確認の列を始めます。
    ///
    /// 責務: 判定が再確認を許す時だけ、即時(前面復帰)または待ち時間の後からの再確認を始めます。
    /// - Parameter immediately: 待たずに1回再確認するかどうか。
    private func restartSessionRecheckIfNeeded(immediately: Bool) {
        guard recheckPolicy.shouldRecheck(phase: state.phase, isSessionCheckUnresolved: isSessionCheckUnresolved) else { return }
        recheckScheduler.start(immediately: immediately) { [weak self] in
            await self?.recheckSession() ?? .resolved
        }
    }

    /// サインイン確認を1回やり直し、結果を状態へ反映します。
    ///
    /// 責務: 再確認すべき状態の時だけ照会し、取り消し後や手動サインイン開始後に戻った結果は捨てます。
    /// - Returns: 確認が解決したか、まだ確認できないか。
    private func recheckSession() async -> AuthenticationSessionRecheckScheduler.Outcome {
        guard recheckPolicy.shouldRecheck(phase: state.phase, isSessionCheckUnresolved: isSessionCheckUnresolved) else {
            return .resolved
        }
        let result: AppleAccountSession??
        do {
            result = .some(try await restoreSession.execute())
        } catch {
            result = nil
        }
        guard !Task.isCancelled,
              recheckPolicy.shouldRecheck(phase: state.phase, isSessionCheckUnresolved: isSessionCheckUnresolved) else {
            return .resolved
        }
        guard let session = result else { return .unresolved }
        applyConfirmedSession(session)
        return .resolved
    }

    /// ログイン待機中の場合に限り免責事項を提示します。
    ///
    /// 責務: Apple認証前の明示同意画面をログイン可能状態だけで開きます。
    private func presentDisclaimerIfPossible() {
        guard state.phase == .signedOut else { return }
        state.failure = nil
        state.isDisclaimerPresented = true
    }

    /// 免責事項が表示中でログイン可能な場合に限りApple認証を開始します。
    ///
    /// 責務: 明示同意済みの1回のAppleログイン要求だけを実行します。
    private func beginSignInIfPossible() {
        guard
            state.phase == .signedOut,
            state.isDisclaimerPresented,
            signInTask == nil
        else { return }

        state.isDisclaimerPresented = false
        state.failure = nil
        state.phase = .signingIn
        isSessionCheckUnresolved = false
        recheckScheduler.cancel()
        signInTask = Task { [weak self] in
            guard let self else { return }
            defer { signInTask = nil }
            do {
                let session = try await signInWithApple.execute()
                sessionRevocation.registerCurrentSession(for: session.userIdentifier)
                startObservingSessionRevocation(for: session.userIdentifier)
                state.session = session
                state.phase = .signedIn
            } catch AppleAccountAuthorizationError.cancelled {
                state.session = nil
                state.phase = .signedOut
            } catch AppleAccountAuthorizationError.unavailable {
                state.session = nil
                state.phase = .signedOut
                state.failure = .serviceUnavailable
            } catch {
                state.session = nil
                state.phase = .signedOut
                state.failure = .signInFailed
            }
        }
    }

    /// 指定アカウントの未受理セッション失効を監視します。
    ///
    /// 責務: 認証済みアカウント1件を端末間失効通知と現在端末のログアウト処理へ結び付けます。
    /// - Parameter userIdentifier: Appleがこのアプリへ割り当てたユーザー識別子。
    private func startObservingSessionRevocation(for userIdentifier: String) {
        sessionRevocation.startObserving(for: userIdentifier) { [weak self] in
            self?.applyRemoteSessionRevocation(for: userIdentifier)
        }
    }

    /// 他端末から失効された現在アカウントを端末内からログアウトします。
    ///
    /// 責務: 1件の遠隔失効を端末内消去結果とログイン画面への状態遷移へ変換します。
    /// - Parameter userIdentifier: 失効通知の対象となったAppleユーザー識別子。
    private func applyRemoteSessionRevocation(for userIdentifier: String) {
        guard
            state.phase == .signedIn,
            state.session?.userIdentifier == userIdentifier
        else { return }

        do {
            try remoteAccountLogout.execute(userIdentifier: userIdentifier)
        } catch {
            state.failure = .remoteLogoutPersistenceFailed
        }
        sessionRevocation.stopObserving()
        state.accountDeletionPhase = .idle
        state.accountDeletionFailure = nil
        state.session = nil
        state.phase = .signedOut
    }
}
