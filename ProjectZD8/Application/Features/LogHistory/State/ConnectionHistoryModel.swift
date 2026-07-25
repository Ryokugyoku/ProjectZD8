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
    /// 現在端末のRawログ容量解放ユースケースです。
    @ObservationIgnored private let releaseRawCache: ReleaseConnectionSessionRawCacheUseCase?
    /// iCloudを含む全端末セッション削除ユースケースです。
    @ObservationIgnored private let deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase?
    /// 自動判別できない停止をユーザー確認済みとして保存するユースケースです。
    @ObservationIgnored private let reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase?
    /// 期限切れRawログをCloudKit保管へ退避するユースケースです。
    @ObservationIgnored private let evictStaleRawLogs: EvictStaleConnectionSessionRawLogsUseCase?
    /// 現在のAppleアカウント識別子です。
    @ObservationIgnored private var accountIdentifier: String?
    /// 古いアカウント同期完了を現在状態へ反映しないための世代です。
    @ObservationIgnored private var syncGeneration: UInt = 0
    /// 現在進行中のCloudKit同期タスクです。
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    /// 現在進行中の単一セッションアップロードタスクです。
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    /// 古いアカウントのアップロード完了を現在状態へ反映しないための世代です。
    @ObservationIgnored private var uploadGeneration: UInt = 0
    /// 現在進行中の全端末削除タスクです。
    @ObservationIgnored private var deletionTask: Task<Void, Never>?

    /// 初期状態とセッション照会先を固定して生成します。
    ///
    /// 責務: 接続履歴表示状態を1件のセッション照会境界へ結び付けます。
    /// - Parameters:
    ///   - state: Platformへ公開する初期状態。
    ///   - repository: アカウント単位のセッション取得先。
    ///   - synchronizeSessions: セッション単位のCloudKit同期ユースケース。
    ///   - releaseRawCache: 現在端末のRawログ容量解放ユースケース。
    ///   - deleteSessionEverywhere: iCloudを含む全端末セッション削除ユースケース。
    ///   - reviewInterruptedSession: ユーザー操作による停止の確認結果を保存するユースケース。
    ///   - evictStaleRawLogs: 3日以上未閲覧のRawログを端末から退避するユースケース。
    init(
        state: ConnectionHistoryState,
        repository: any ConnectionSessionRepository,
        synchronizeSessions: SynchronizeConnectionSessionsUseCase? = nil,
        releaseRawCache: ReleaseConnectionSessionRawCacheUseCase? = nil,
        deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase? = nil,
        reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase? = nil,
        evictStaleRawLogs: EvictStaleConnectionSessionRawLogsUseCase? = nil
    ) {
        self.state = state
        self.repository = repository
        self.synchronizeSessions = synchronizeSessions
        self.releaseRawCache = releaseRawCache
        self.deleteSessionEverywhere = deleteSessionEverywhere
        self.reviewInterruptedSession = reviewInterruptedSession
        self.evictStaleRawLogs = evictStaleRawLogs
    }

    /// 空の履歴状態と指定セッション照会先を使って生成します。
    ///
    /// 責務: 1件のセッション照会境界を標準的な接続履歴モデルへ変換します。
    /// - Parameters:
    ///   - repository: アカウント単位のセッション取得先。
    ///   - synchronizeSessions: セッション単位のCloudKit同期ユースケース。
    ///   - releaseRawCache: 現在端末のRawログ容量解放ユースケース。
    ///   - deleteSessionEverywhere: iCloudを含む全端末セッション削除ユースケース。
    ///   - reviewInterruptedSession: ユーザー操作による停止の確認結果を保存するユースケース。
    ///   - evictStaleRawLogs: 3日以上未閲覧のRawログを端末から退避するユースケース。
    convenience init(
        repository: any ConnectionSessionRepository,
        synchronizeSessions: SynchronizeConnectionSessionsUseCase? = nil,
        releaseRawCache: ReleaseConnectionSessionRawCacheUseCase? = nil,
        deleteSessionEverywhere: DeleteConnectionSessionEverywhereUseCase? = nil,
        reviewInterruptedSession: ReviewInterruptedConnectionSessionUseCase? = nil,
        evictStaleRawLogs: EvictStaleConnectionSessionRawLogsUseCase? = nil
    ) {
        self.init(
            state: ConnectionHistoryState(),
            repository: repository,
            synchronizeSessions: synchronizeSessions,
            releaseRawCache: releaseRawCache,
            deleteSessionEverywhere: deleteSessionEverywhere,
            reviewInterruptedSession: reviewInterruptedSession,
            evictStaleRawLogs: evictStaleRawLogs
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
        case .localDataChanged: loadSessions()
        case let .automaticUploadChanged(isEnabled): state.automaticUploadEnabled = isEnabled
        case let .sessionUploadRequested(sessionID): uploadSession(sessionID)
        case .sessionUploadFailureDismissed: state.uploadFailureSessionID = nil
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
        uploadTask?.cancel()
        uploadTask = nil
        deletionTask?.cancel()
        deletionTask = nil
        syncGeneration &+= 1
        uploadGeneration &+= 1
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
        let precedingUploadTask = uploadTask
        syncTask?.cancel()
        syncTask = nil
        uploadTask?.cancel()
        uploadTask = nil
        syncGeneration &+= 1
        uploadGeneration &+= 1
        state.syncPhase = .idle
        state.uploadingSessionID = nil
        state.uploadProgress = nil
        deletionTask = Task { [weak self] in
            await precedingSyncTask?.value
            await precedingUploadTask?.value
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
        guard syncTask == nil else { return }
        syncGeneration &+= 1
        let generation = syncGeneration
        let evictStaleRawLogs = evictStaleRawLogs
        state.syncPhase = .syncing
        syncTask = Task { [weak self] in
            do {
                try await synchronizeSessions.execute(
                    accountIdentifier: accountIdentifier,
                    uploadsPendingSessions: false
                )
                try evictStaleRawLogs?.execute(accountIdentifier: accountIdentifier)
                guard let self, self.syncGeneration == generation, self.accountIdentifier == accountIdentifier else { return }
                self.syncTask = nil
                self.loadSessions()
                self.state.syncPhase = .synchronized
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.syncGeneration == generation, self.accountIdentifier == accountIdentifier else { return }
                self.syncTask = nil
                self.state.syncPhase = .failed
            }
        }
    }

    /// 指定された未送信セッションのiCloudアップロードを開始します。
    ///
    /// 責務: 1件の送信可能な終了済みセッションIDを重複しない個別CloudKit転送へ変換します。
    /// - Parameter sessionID: アップロード対象の接続セッションID。
    private func uploadSession(_ sessionID: ConnectionSessionID) {
        guard let accountIdentifier,
              let synchronizeSessions,
              uploadTask == nil,
              let session = state.sessions.first(where: { $0.id == sessionID }),
              session.endedAt != nil,
              session.rawLogSummary.localState != .removed,
              session.rawLogSummary.cloudState != .uploaded else { return }
        uploadGeneration &+= 1
        let generation = uploadGeneration
        state.uploadingSessionID = sessionID
        state.uploadProgress = 0
        state.uploadFailureSessionID = nil
        uploadTask = Task { [weak self] in
            do {
                try await synchronizeSessions.upload(
                    sessionID: sessionID,
                    accountIdentifier: accountIdentifier,
                    progress: { [weak self] progress in
                        guard let self,
                              self.uploadGeneration == generation,
                              self.accountIdentifier == accountIdentifier else { return }
                        self.state.uploadProgress = min(max(progress, 0), 1)
                    }
                )
                guard let self,
                      self.uploadGeneration == generation,
                      self.accountIdentifier == accountIdentifier else { return }
                self.uploadTask = nil
                self.state.uploadingSessionID = nil
                self.state.uploadProgress = nil
                self.loadSessions()
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.uploadGeneration == generation,
                      self.accountIdentifier == accountIdentifier else { return }
                self.uploadTask = nil
                self.state.uploadingSessionID = nil
                self.state.uploadProgress = nil
                self.state.uploadFailureSessionID = sessionID
                self.loadSessions()
            }
        }
    }

    /// 指定セッションのローカルRawログ除去確認を準備します。
    ///
    /// 責務: 1件のセッションIDをiCloud保管証跡付きの端末容量解放確認状態へ変換します。
    /// - Parameter sessionID: 除去候補の接続セッションID。
    private func prepareRawRemoval(sessionID: ConnectionSessionID) {
        guard let releaseRawCache,
              let session = state.sessions.first(where: { $0.id == sessionID }) else { return }
        let decision = releaseRawCache.decision(for: session)
        guard decision != .unavailable else { return }
        state.rawRemovalPrompt = ConnectionSessionRawRemovalPrompt(
            sessionID: sessionID,
            decision: decision,
            recordCount: session.rawLogSummary.recordCount,
            byteCount: session.rawLogSummary.byteCount
        )
    }

    /// ユーザー確認済みのRawログを現在端末から除去します。
    ///
    /// 責務: 現在の除去確認状態をローカルRawログ削除と履歴再読込へ変換します。
    private func confirmRawRemoval() {
        guard let prompt = state.rawRemovalPrompt,
              let session = state.sessions.first(where: { $0.id == prompt.sessionID }),
              let releaseRawCache else { return }
        do {
            try releaseRawCache.execute(session: session)
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
