import Observation

/// アカウント単位の接続セッション照会を履歴表示状態へ変換します。
@MainActor
@Observable
final class ConnectionHistoryModel {
    /// Platformが描画する現在の履歴状態です。
    var state: ConnectionHistoryState
    /// セッションの永続化照会境界です。
    @ObservationIgnored private let repository: any ConnectionSessionRepository
    /// 現在のAppleアカウント識別子です。
    @ObservationIgnored private var accountIdentifier: String?

    /// 初期状態とセッション照会先を固定して生成します。
    ///
    /// 責務: 接続履歴表示状態を1件のセッション照会境界へ結び付けます。
    /// - Parameters:
    ///   - state: Platformへ公開する初期状態。
    ///   - repository: アカウント単位のセッション取得先。
    init(
        state: ConnectionHistoryState,
        repository: any ConnectionSessionRepository
    ) {
        self.state = state
        self.repository = repository
    }

    /// 空の履歴状態と指定セッション照会先を使って生成します。
    ///
    /// 責務: 1件のセッション照会境界を標準的な接続履歴モデルへ変換します。
    /// - Parameter repository: アカウント単位のセッション取得先。
    convenience init(repository: any ConnectionSessionRepository) {
        self.init(state: ConnectionHistoryState(), repository: repository)
    }

    /// 型付き操作を履歴照会へ変換します。
    ///
    /// 責務: 1件のLogHistory操作をアカウント変更または再読込へ振り分けます。
    /// - Parameter action: AppまたはPlatformから通知された操作。
    func send(_ action: ConnectionHistoryAction) {
        switch action {
        case let .accountIdentifierChanged(identifier): activateAccount(identifier)
        case .refreshRequested: loadSessions()
        }
    }

    /// 新しいアカウントへ履歴読込範囲を切り替えます。
    ///
    /// 責務: 1件の認証識別子変更を履歴状態の初期化と再読込へ反映します。
    /// - Parameter identifier: 新しいAppleアカウント識別子。
    private func activateAccount(_ identifier: String?) {
        guard identifier != accountIdentifier else { return }
        accountIdentifier = identifier
        state = ConnectionHistoryState()
        guard identifier?.isEmpty == false else { return }
        loadSessions()
    }

    /// 現在アカウントの接続履歴を保存先から読み込みます。
    ///
    /// 責務: 現在の1件のアカウントスコープへ接続履歴照会結果を反映します。
    private func loadSessions() {
        guard let accountIdentifier else { return }
        state.phase = .loading
        do {
            state.sessions = try repository.sessions(for: accountIdentifier)
            state.phase = .loaded
            state.failureKey = nil
        } catch {
            state.phase = .failed
            state.failureKey = "history.error.storage"
        }
    }
}
