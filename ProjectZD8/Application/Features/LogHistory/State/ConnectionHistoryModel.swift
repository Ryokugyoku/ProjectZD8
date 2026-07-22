import Observation

/// アカウント単位の接続セッション照会を履歴表示状態へ変換します。
@MainActor
@Observable
final class ConnectionHistoryModel {
    /// Platformが描画する現在の履歴状態です。
    var state: ConnectionHistoryState
    /// セッションの永続化照会境界です。
    @ObservationIgnored private let repository: any ConnectionSessionRepository
    /// セッション単位のCloudKit同期ユースケースです。
    @ObservationIgnored private let synchronizeSessions: SynchronizeConnectionSessionsUseCase?
    /// iPhoneローカルRawログ除去ユースケースです。
    @ObservationIgnored private let removeIPhoneRawLog: RemoveIPhoneSessionRawLogUseCase?
    /// macOSの全端末セッション削除ユースケースです。
    @ObservationIgnored private let deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase?
    /// 自動判別できない停止をユーザー確認済みとして保存するユースケースです。
    @ObservationIgnored private let reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase?
    /// 現在のAppleアカウント識別子です。
    @ObservationIgnored private var accountIdentifier: String?
    /// 古いアカウント同期完了を現在状態へ反映しないための世代です。
    @ObservationIgnored private var syncGeneration: UInt = 0
    /// 現在進行中のCloudKit同期タスクです。
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    /// 現在進行中の全端末削除タスクです。
    @ObservationIgnored private var deletionTask: Task<Void, Never>?

    /// 初期状態とセッション照会先を固定して生成します。
    ///
    /// 責務: 接続履歴表示状態を1件のセッション照会境界へ結び付けます。
    /// - Parameters:
    ///   - state: Platformへ公開する初期状態。
    ///   - repository: アカウント単位のセッション取得先。
    ///   - synchronizeSessions: セッション単位のCloudKit同期ユースケース。
    ///   - removeIPhoneRawLog: iPhoneローカルRawログ除去ユースケース。
    ///   - deleteSessionEverywhere: macOSの全端末セッション削除ユースケース。
    ///   - reviewInterruptedSession: ユーザー操作による停止の確認結果を保存するユースケース。
    init(
        state: ConnectionHistoryState,
        repository: any ConnectionSessionRepository,
        synchronizeSessions: SynchronizeConnectionSessionsUseCase? = nil,
        removeIPhoneRawLog: RemoveIPhoneSessionRawLogUseCase? = nil,
        deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase? = nil,
        reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase? = nil
    ) {
        self.state = state
        self.repository = repository
        self.synchronizeSessions = synchronizeSessions
        self.removeIPhoneRawLog = removeIPhoneRawLog
        self.deleteSessionEverywhere = deleteSessionEverywhere
        self.reviewInterruptedSession = reviewInterruptedSession
    }

    /// 空の履歴状態と指定セッション照会先を使って生成します。
    ///
    /// 責務: 1件のセッション照会境界を標準的な接続履歴モデルへ変換します。
    /// - Parameters:
    ///   - repository: アカウント単位のセッション取得先。
    ///   - synchronizeSessions: セッション単位のCloudKit同期ユースケース。
    ///   - removeIPhoneRawLog: iPhoneローカルRawログ除去ユースケース。
    ///   - deleteSessionEverywhere: macOSの全端末セッション削除ユースケース。
    ///   - reviewInterruptedSession: ユーザー操作による停止の確認結果を保存するユースケース。
    convenience init(
        repository: any ConnectionSessionRepository,
        synchronizeSessions: SynchronizeConnectionSessionsUseCase? = nil,
        removeIPhoneRawLog: RemoveIPhoneSessionRawLogUseCase? = nil,
        deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase? = nil,
        reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase? = nil
    ) {
        self.init(
            state: ConnectionHistoryState(),
            repository: repository,
            synchronizeSessions: synchronizeSessions,
            removeIPhoneRawLog: removeIPhoneRawLog,
            deleteSessionEverywhere: deleteSessionEverywhere,
            reviewInterruptedSession: reviewInterruptedSession
        )
    }

    /// 型付き操作を履歴照会へ変換します。
    ///
    /// 責務: 1件のLogHistory操作を対応する履歴状態変更またはユースケースへ振り分けます。
    /// - Parameter action: AppまたはPlatformから通知された操作。
    func send(_ action: ConnectionHistoryAction) {
        switch action {
        case let .accountIdentifierChanged(identifier): activateAccount(identifier)
        case .refreshRequested: refreshSessions()
        case let .filterStartDateChanged(date): state.filterStartDate = date
        case let .filterEndDateChanged(date): state.filterEndDate = date
        case let .endReasonFilterChanged(filter): state.endReasonFilter = filter
        case let .sortOrderChanged(order): state.sortOrder = order
        case .filtersReset: resetFilters()
        case let .stopReviewRequested(sessionID): prepareStopReview(sessionID: sessionID)
        case .stopReviewConfirmed: confirmStopReview()
        case .stopReviewCancelled: state.stopReviewPrompt = nil
        case .stopReviewFailureDismissed: state.stopReviewFailureKey = nil
        case let .localRawRemovalRequested(sessionID): prepareRawRemoval(sessionID: sessionID)
        case .localRawRemovalConfirmed: confirmRawRemoval()
        case .localRawRemovalCancelled: state.rawRemovalPrompt = nil
        case let .sessionDeletionRequested(sessionID): prepareSessionDeletion(sessionID: sessionID)
        case .sessionDeletionConfirmed: confirmSessionDeletion()
        case .sessionDeletionCancelled: state.sessionDeletionPrompt = nil
        case .sessionDeletionFailureDismissed: state.sessionDeletionFailureKey = nil
        }
    }

    /// 指定セッションのユーザー操作停止確認を準備します。
    ///
    /// 責務: 1件の確認可能なセッションIDを観測済み終了理由を含む確認表示へ変換します。
    /// - Parameter sessionID: 確認対象の接続セッションID。
    private func prepareStopReview(sessionID: ConnectionSessionID) {
        guard reviewInterruptedSession != nil,
              let session = state.sessions.first(where: { $0.id == sessionID }),
              session.needsStopReview,
              let reason = session.endReason else { return }
        state.stopReviewFailureKey = nil
        state.stopReviewPrompt = ConnectionSessionStopReviewPrompt(
            sessionID: sessionID,
            observedReason: reason
        )
    }

    /// 表示中の停止確認を正式データ扱いとして保存します。
    ///
    /// 責務: 現在の停止確認内容をユーザー操作停止の永続化と履歴再読込へ変換します。
    private func confirmStopReview() {
        guard let prompt = state.stopReviewPrompt,
              let session = state.sessions.first(where: { $0.id == prompt.sessionID }),
              let reviewInterruptedSession else { return }
        do {
            _ = try reviewInterruptedSession.execute(session: session)
            state.stopReviewPrompt = nil
            loadSessions()
        } catch {
            state.stopReviewPrompt = nil
            state.stopReviewFailureKey = "history.stop_review.error"
        }
    }

    /// セッション一覧の絞り込み条件を標準値へ戻します。
    ///
    /// 責務: 現在の履歴状態から日付範囲と終了理由条件だけを初期化します。
    private func resetFilters() {
        state.filterStartDate = nil
        state.filterEndDate = nil
        state.endReasonFilter = .all
    }

    /// 新しいアカウントへ履歴読込範囲を切り替えます。
    ///
    /// 責務: 1件の認証識別子変更を履歴状態の初期化と再読込へ反映します。
    /// - Parameter identifier: 新しいAppleアカウント識別子。
    private func activateAccount(_ identifier: String?) {
        guard identifier != accountIdentifier else { return }
        accountIdentifier = identifier
        syncTask?.cancel()
        syncTask = nil
        deletionTask?.cancel()
        deletionTask = nil
        syncGeneration &+= 1
        state = ConnectionHistoryState()
        guard identifier?.isEmpty == false else { return }
        refreshSessions()
    }

    /// 指定セッションの全端末物理削除確認を準備します。
    ///
    /// 責務: 1件の終了済みセッションIDを全端末削除警告の表示状態へ変換します。
    /// - Parameter sessionID: 削除候補の接続セッションID。
    private func prepareSessionDeletion(sessionID: ConnectionSessionID) {
        guard deleteSessionEverywhere != nil,
              state.deletingSessionID == nil,
              let session = state.sessions.first(where: { $0.id == sessionID }),
              session.endedAt != nil else { return }
        state.sessionDeletionPrompt = ConnectionSessionDeletionPrompt(
            sessionID: sessionID,
            recordCount: session.rawLogSummary.recordCount,
            byteCount: session.rawLogSummary.byteCount
        )
    }

    /// 確認済みセッションを全端末削除処理へ渡します。
    ///
    /// 責務: 現在の削除確認状態をCloudKit削除伝播とローカル物理削除へ変換します。
    private func confirmSessionDeletion() {
        guard let prompt = state.sessionDeletionPrompt,
              let session = state.sessions.first(where: { $0.id == prompt.sessionID }),
              let deleteSessionEverywhere,
              state.deletingSessionID == nil else { return }
        state.sessionDeletionPrompt = nil
        state.sessionDeletionFailureKey = nil
        state.deletingSessionID = session.id
        let precedingSyncTask = syncTask
        syncTask?.cancel()
        syncTask = nil
        syncGeneration &+= 1
        state.syncPhase = .idle
        deletionTask = Task { [weak self] in
            await precedingSyncTask?.value
            do {
                try await deleteSessionEverywhere.execute(session: session)
                guard let self else { return }
                self.state.deletingSessionID = nil
                self.loadSessions()
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.state.deletingSessionID = nil
                self.state.sessionDeletionFailureKey = "history.delete.error"
            }
        }
    }

    /// ローカル履歴を即時反映してからCloudKit同期を開始します。
    ///
    /// 責務: 現在アカウントの更新要求をローカル表示と最新世代の端末間同期へ変換します。
    private func refreshSessions() {
        loadSessions()
        guard let accountIdentifier, let synchronizeSessions else { return }
        syncTask?.cancel()
        syncGeneration &+= 1
        let generation = syncGeneration
        state.syncPhase = .syncing
        syncTask = Task { [weak self] in
            do {
                try await synchronizeSessions.execute(accountIdentifier: accountIdentifier)
                guard let self, self.syncGeneration == generation, self.accountIdentifier == accountIdentifier else { return }
                self.loadSessions()
                self.state.syncPhase = .synchronized
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.syncGeneration == generation, self.accountIdentifier == accountIdentifier else { return }
                self.state.syncPhase = .failed
            }
        }
    }

    /// 指定セッションのローカルRawログ除去確認を準備します。
    ///
    /// 責務: 1件のセッションIDをMac取込証跡付きのiPhone除去確認状態へ変換します。
    /// - Parameter sessionID: 除去候補の接続セッションID。
    private func prepareRawRemoval(sessionID: ConnectionSessionID) {
        guard let removeIPhoneRawLog,
              let session = state.sessions.first(where: { $0.id == sessionID }) else { return }
        let decision = removeIPhoneRawLog.decision(for: session)
        guard decision != .unavailable else { return }
        state.rawRemovalPrompt = ConnectionSessionRawRemovalPrompt(
            sessionID: sessionID,
            decision: decision,
            recordCount: session.rawLogSummary.recordCount,
            byteCount: session.rawLogSummary.byteCount
        )
    }

    /// ユーザー確認済みのRawログをiPhoneから除去します。
    ///
    /// 責務: 現在の除去確認状態をローカルRawログ削除と履歴再読込へ変換します。
    private func confirmRawRemoval() {
        guard let prompt = state.rawRemovalPrompt,
              let session = state.sessions.first(where: { $0.id == prompt.sessionID }),
              let removeIPhoneRawLog else { return }
        do {
            try removeIPhoneRawLog.execute(session: session)
            state.rawRemovalPrompt = nil
            loadSessions()
        } catch {
            state.failureKey = "history.error.local_removal"
        }
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
