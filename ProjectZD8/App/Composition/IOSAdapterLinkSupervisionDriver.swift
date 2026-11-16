#if os(iOS)
import Observation

/// アプリ側の事実(起動・認証状態・既定アダプター設定・前面復帰・背面移行)を常駐リンク監視の入力へ伝えます。
///
/// 稼働条件の判断は `AdapterLinkSupervisionUseCase` に任せ、この型は事実を対応する入力へ写すだけです。
/// 認証状態は画面の表示を待たずに観測するため、バックグラウンド起動・状態復元でも伝わります。
@MainActor
final class IOSAdapterLinkSupervisionDriver {
    /// 常駐リンク監視です。
    private let supervision: AdapterLinkSupervisionUseCase

    /// 認証状態の持ち主です。
    private let authentication: AuthenticationSessionModel

    /// サインイン中アカウントの識別子(サインアウトでは `nil`)を記録側へ伝える処理です。
    private let accountIdentifierDidChange: @MainActor (String?) -> Void

    /// 最後に伝えた認証段階です。同じ段階の再通知を省くために使います。
    private var lastAuthenticationPhase: AuthenticationPhase?

    /// 最後に伝えたアカウント識別子です。
    private var lastAccountIdentifier: String?

    /// 常駐リンク監視と認証状態の持ち主を固定して生成します。
    ///
    /// 責務: 事実の送り先と観測元を結び付けます。観測は `launch()` で始めます。
    /// - Parameters:
    ///   - supervision: 常駐リンク監視。
    ///   - authentication: 認証状態の持ち主。
    ///   - accountIdentifierDidChange: サインイン中アカウントの識別子を記録側へ伝える処理。
    init(
        supervision: AdapterLinkSupervisionUseCase,
        authentication: AuthenticationSessionModel,
        accountIdentifierDidChange: @escaping @MainActor (String?) -> Void
    ) {
        self.supervision = supervision
        self.authentication = authentication
        self.accountIdentifierDidChange = accountIdentifierDidChange
    }

    /// アプリ起動時に監視を始めます。画面の表示を待たない場所(App の生成時)で1回だけ呼びます。
    ///
    /// 責務: 保存済み認証セッションの確認を始め、監視を開始し、現在の認証状態を伝えて以後の変化の観測を始めます。
    func launch() {
        authentication.send(.appeared)
        supervision.start()
        applyAuthenticationState()
        observeAuthenticationState()
    }

    /// アプリが前面へ戻ったこと(scenePhase が active)を伝えます。
    ///
    /// 責務: 前面復帰を監視の入力へ写します。
    func appDidBecomeActive() {
        supervision.appDidBecomeActive()
    }

    /// アプリが背面へ移ったこと(scenePhase が background)を伝えます。
    ///
    /// 責務: 背面移行を監視の入力へ写します(前面かどうかを監視の稼働条件にするため)。
    func appDidEnterBackground() {
        supervision.appDidEnterBackground()
    }

    /// 既定アダプター設定が保存・削除・変更されたことを伝えます。
    ///
    /// 責務: 設定変更を監視の入力へ写します(監視が保存先から読み直します)。
    func defaultAdapterPreferenceDidChange() {
        supervision.defaultAdapterPreferenceDidChange()
    }

    /// 認証状態の次の変化を1回だけ観測します。変化のたびに観測を登録し直します。
    ///
    /// 責務: 認証段階とセッションの読み取りを観測へ登録し、変化後の値をメインアクターで反映します。
    private func observeAuthenticationState() {
        withObservationTracking {
            _ = authentication.state.phase
            _ = authentication.state.session
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyAuthenticationState()
                self?.observeAuthenticationState()
            }
        }
    }

    /// 現在の認証状態を監視と記録側へ伝えます。
    ///
    /// 責務: 段階が変わった時だけサインイン有無を監視へ伝え、サインイン/サインアウトのアカウント識別子を記録側へ伝えます。
    /// サインアウト(アカウント削除・他端末からのログアウトを含む)では既定アダプター設定が消えている場合があるので読み直させます。
    private func applyAuthenticationState() {
        let state = authentication.state
        let accountIdentifier: String? = switch state.phase {
        case .signedIn: state.session?.userIdentifier
        case .signedOut: nil
        default: lastAccountIdentifier
        }
        if accountIdentifier != lastAccountIdentifier {
            lastAccountIdentifier = accountIdentifier
            accountIdentifierDidChange(accountIdentifier)
        }
        guard state.phase != lastAuthenticationPhase else { return }
        lastAuthenticationPhase = state.phase
        supervision.authenticationDidChange(isSignedIn: state.phase == .signedIn)
        if state.phase == .signedOut {
            supervision.defaultAdapterPreferenceDidChange()
        }
    }
}
#endif
