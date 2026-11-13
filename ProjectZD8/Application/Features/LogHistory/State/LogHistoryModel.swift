import Foundation
import Observation

/// 記録済みログの一覧、絞り込み、詳細、削除、領域解放を調整します。
@MainActor
@Observable
final class LogHistoryModel {
    /// 画面が描画する現在状態です。
    private(set) var state = LogHistoryState()

    @ObservationIgnored private let sessions: any SessionRepository
    @ObservationIgnored private let vehicles: any VehicleRepository
    @ObservationIgnored private let changes: any StoreChangeObserving
    @ObservationIgnored private let buildGroups = BuildLogHistoryGroupsUseCase()
    @ObservationIgnored private let deleteSession: DeleteLogHistorySessionUseCase
    @ObservationIgnored private let freeUpSpace: FreeUpSessionSpaceUseCase
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var driveSessions: [DriveSession] = []
    @ObservationIgnored private var vehicleNames: [VehicleID: String] = [:]

    /// 永続化契約を注入してモデルを生成します。
    ///
    /// 責務: ログ履歴の状態遷移を永続化契約へ結び付けます。
    init(sessions: any SessionRepository, vehicles: any VehicleRepository, changes: any StoreChangeObserving) {
        self.sessions = sessions
        self.vehicles = vehicles
        self.changes = changes
        deleteSession = DeleteLogHistorySessionUseCase(sessions: sessions)
        freeUpSpace = FreeUpSessionSpaceUseCase(sessions: sessions)
    }

    /// 1件の操作を状態へ反映します。永続化を伴う操作は非同期で処理します。
    ///
    /// 責務: 画面からの操作を状態更新または非同期処理へ振り分けます。
    func send(_ action: LogHistoryAction) {
        switch action {
        case .started, .refreshRequested, .deleteConfirmed, .freeUpSpaceConfirmed:
            Task { await perform(action) }
        default:
            applySynchronously(action)
        }
    }

    /// 1件の操作を処理し、完了まで待ちます。
    ///
    /// 責務: 全操作の処理本体です。テストと合成はこれを待って結果を確認できます。
    func perform(_ action: LogHistoryAction) async {
        switch action {
        case .started:
            startObserving()
            state.loadPhase = .loading
            await refresh()
        case .refreshRequested: await refresh()
        case .deleteConfirmed: await confirmDeletion()
        case .freeUpSpaceConfirmed: await confirmFreeUp()
        default: applySynchronously(action)
        }
    }

    /// 責務: 永続化を伴わない操作を状態へ反映します。
    private func applySynchronously(_ action: LogHistoryAction) {
        switch action {
        case .stopped: stopObserving()
        case let .filterChanged(filter):
            state.filter = filter
            rebuild()
        case .filterReset:
            state.filter = LogHistoryFilter()
            rebuild()
        case let .sortOrderChanged(order):
            state.sortOrder = order
            rebuild()
        case let .detailRequested(id): openDetail(id)
        case .detailClosed: state.detail = nil
        case let .deleteRequested(id): requestDeletion(id)
        case .deleteCancelled: state.pendingDeletion = nil
        case let .freeUpSpaceRequested(id): requestFreeUp(id)
        case .freeUpSpaceCancelled: state.pendingFreeUp = nil
        case let .analysisRequested(id): requestAnalysis(id)
        case .analysisRequestHandled: state.analysisRequest = nil
        case .failureDismissed: state.failure = nil
        default: break
        }
    }

    // MARK: - Observation

    /// 責務: セッションと車両の変更通知を購読して自動で再読み込みします。
    private func startObserving() {
        guard observation == nil else { return }
        let stream = changes.changes(in: [.sessions, .vehicles])
        observation = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                await self.refresh()
            }
        }
    }

    /// 責務: 変更通知の購読を止めます。
    private func stopObserving() {
        observation?.cancel()
        observation = nil
    }

    // MARK: - Loading

    /// 責務: セッションと車両名を読み直して表示用の状態を作り直します。
    private func refresh() async {
        do {
            driveSessions = try await sessions.sessions(for: nil)
            vehicleNames = Dictionary(
                try await vehicles.vehicles().map { ($0.id, $0.name) },
                uniquingKeysWith: { _, latest in latest }
            )
            state.loadPhase = .loaded
            rebuild()
        } catch {
            state.loadPhase = .loaded
            state.failure = .loadFailed
        }
    }

    /// 責務: 読み込み済みのセッションから、一覧・グループ・詳細を作り直します。
    private func rebuild() {
        let rows = driveSessions.map(LogHistorySessionRow.init(session:))
        let finished = rows.filter { !$0.isRecording }
        state.activeSessions = rows.filter(\.isRecording).sorted { $0.startedAt > $1.startedAt }
        state.totalFinishedCount = finished.count
        state.groups = buildGroups.execute(rows: finished, vehicleNames: vehicleNames, filter: state.filter, sortOrder: state.sortOrder)
        if let open = state.detail {
            state.detail = driveSessions.first { $0.id == open.row.id }
                .map { LogHistorySessionDetail(session: $0, vehicleName: vehicleNames[$0.vehicleID]) }
        }
    }

    // MARK: - Detail, analysis

    /// 責務: 読み込み済みのセッションから詳細を開きます。
    private func openDetail(_ id: SessionID) {
        guard let session = driveSessions.first(where: { $0.id == id }) else {
            state.failure = .sessionNotFound
            return
        }
        state.detail = LogHistorySessionDetail(session: session, vehicleName: vehicleNames[session.vehicleID])
    }

    /// 責務: 分析を求められたセッションをシェルへ伝えます。
    private func requestAnalysis(_ id: SessionID) {
        guard driveSessions.contains(where: { $0.id == id }) else {
            state.failure = .sessionNotFound
            return
        }
        state.analysisRequest = id
    }

    // MARK: - Deletion

    /// 責務: 削除の確認を求めます。記録中のセッションは失敗にします。
    private func requestDeletion(_ id: SessionID) {
        guard let session = driveSessions.first(where: { $0.id == id }) else {
            state.failure = .sessionNotFound
            return
        }
        guard !session.isRecording else {
            state.failure = .deleteRefusedWhileRecording
            return
        }
        state.pendingDeletion = prompt(for: session)
    }

    /// 責務: 確認済みの削除を実行します。
    private func confirmDeletion() async {
        guard let prompt = state.pendingDeletion else { return }
        state.pendingDeletion = nil
        do {
            try await deleteSession.execute(prompt.sessionID)
            if state.detail?.row.id == prompt.sessionID { state.detail = nil }
            await refresh()
        } catch let failure as LogHistoryFailure {
            state.failure = failure
        } catch {
            state.failure = .deleteFailed
        }
    }

    // MARK: - Free up space

    /// 責務: 領域解放の確認を求めます。解放できないセッションは失敗にします。
    private func requestFreeUp(_ id: SessionID) {
        guard let session = driveSessions.first(where: { $0.id == id }) else {
            state.failure = .sessionNotFound
            return
        }
        guard LogHistorySessionRow(session: session).canFreeUpSpace else {
            state.failure = .freeUpSpaceNotAllowed
            return
        }
        state.pendingFreeUp = prompt(for: session)
    }

    /// 責務: 確認済みの領域解放を実行します。
    private func confirmFreeUp() async {
        guard let prompt = state.pendingFreeUp else { return }
        state.pendingFreeUp = nil
        do {
            try await freeUpSpace.execute(prompt.sessionID)
            await refresh()
        } catch let failure as LogHistoryFailure {
            state.failure = failure
        } catch {
            state.failure = .freeUpSpaceFailed
        }
    }

    /// 責務: セッションから確認画面の内容を作ります。
    private func prompt(for session: DriveSession) -> LogHistorySessionPrompt {
        LogHistorySessionPrompt(
            sessionID: session.id,
            vehicleName: vehicleNames[session.vehicleID],
            startedAt: session.startedAt,
            sampleCount: session.sampleCount,
            payloadByteCount: session.payloadByteCount
        )
    }
}
