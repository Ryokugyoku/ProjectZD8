import Foundation
import Observation

/// 分析ワークベンチの状態を管理し、セッションの読み込み・iCloudからの復元・長期傾向の集計を進めます。
@MainActor
@Observable
final class AnalysisModel {
    /// 画面が読む現在の状態です。
    private(set) var state: AnalysisState

    private let sessions: any SessionRepository
    private let vehicles: any VehicleRepository
    private let cloudSync: any CloudSyncPort
    private let buildDataset: BuildAnalysisDatasetUseCase
    private let buildTrend: BuildVehicleTrendDatasetUseCase
    private let store: AnalysisDatasetStore

    /// 読み込みの世代です。古い読み込みの結果が新しい状態を壊さないために使います。
    private var generation = 0
    /// 一覧読み込みの世代です。
    private var catalogGeneration = 0
    private var activeTask: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?
    /// ダウンロードの承諾待ちセッションと、承諾後に行う読み込み方法です。
    private var pendingDownload: (id: SessionID, replace: Bool)?

    /// モデルを生成します。
    ///
    /// 責務: 分析に必要な読み出し元・ユースケース・データ置き場と表示言語を束ねます。
    init(
        languageCode: String,
        sessions: any SessionRepository,
        vehicles: any VehicleRepository,
        cloudSync: any CloudSyncPort,
        buildDataset: BuildAnalysisDatasetUseCase,
        buildTrend: BuildVehicleTrendDatasetUseCase,
        store: AnalysisDatasetStore
    ) {
        state = AnalysisState(languageCode: languageCode)
        self.sessions = sessions
        self.vehicles = vehicles
        self.cloudSync = cloudSync
        self.buildDataset = buildDataset
        self.buildTrend = buildTrend
        self.store = store
    }

    /// 操作を受け付けます。時間のかかる操作は新しい操作が来ると取り消されます。
    ///
    /// 責務: 画面からの `AnalysisAction` を非同期に処理へ流します。
    func send(_ action: AnalysisAction) {
        switch action {
        case .openSession, .addComparisonSession, .confirmDownload, .requestTrend:
            activeTask?.cancel()
            activeTask = Task { [weak self] in await self?.perform(action) }
        case .appeared, .selectVehicle:
            catalogTask?.cancel()
            catalogTask = Task { [weak self] in await self?.perform(action) }
        default:
            Task { [weak self] in await self?.perform(action) }
        }
    }

    /// 操作を処理し、完了まで待ちます。テストと呼び出し側の直列実行に使います。
    ///
    /// 責務: 1件の `AnalysisAction` を状態の更新へ変換します。
    func perform(_ action: AnalysisAction) async {
        switch action {
        case .appeared:
            await loadCatalog()
        case .selectVehicle(let id):
            await selectVehicle(id)
        case .openSession(let id):
            await open(id, replacing: true)
        case .addComparisonSession(let id):
            await open(id, replacing: false)
        case .removeSession(let id):
            removeSession(id)
        case .confirmDownload:
            await confirmDownload()
        case .declineDownload:
            pendingDownload = nil
            state.phase = state.loadedSessions.isEmpty ? .idle : .ready
        case .requestTrend(let includeDemo):
            await loadTrend(includeDemo: includeDemo)
        case .requestSessionPicker(let purpose):
            if purpose == .addComparison, state.isAtSessionLimit {
                state.phase = .failed(.tooManySessions)
            } else {
                state.pickerPurpose = purpose
            }
        case .dismissSessionPicker:
            state.pickerPurpose = nil
        case .receiveExport(let request):
            state.pendingExport = request
        case .finishExport:
            state.pendingExport = nil
        case .dismissFailure:
            if case .failed = state.phase { state.phase = state.loadedSessions.isEmpty ? .idle : .ready }
        }
    }

    // MARK: - 車両とセッションの一覧

    /// 責務: 車両一覧を読み込み、未選択なら先頭の車両のセッションを読み込みます。
    private func loadCatalog() async {
        catalogGeneration += 1
        let token = catalogGeneration
        if state.phase == .idle { state.phase = .loadingCatalog }
        do {
            let all = try await vehicles.vehicles()
            guard token == catalogGeneration else { return }
            state.vehicles = all.map { AnalysisVehicleOption(id: $0.id, name: $0.name) }
            if state.selectedVehicleID == nil { state.selectedVehicleID = all.first?.id }
            if let selected = state.selectedVehicleID {
                try await refreshSessionOptions(for: selected, token: token)
            }
            guard token == catalogGeneration else { return }
            if state.phase == .loadingCatalog { state.phase = .idle }
        } catch is CancellationError {
            return
        } catch {
            guard token == catalogGeneration else { return }
            state.phase = .failed(.store)
        }
    }

    /// 責務: 車両を切り替え、そのセッション一覧を読み込みます。
    private func selectVehicle(_ id: VehicleID) async {
        catalogGeneration += 1
        let token = catalogGeneration
        state.selectedVehicleID = id
        state.sessionOptions = []
        do {
            try await refreshSessionOptions(for: id, token: token)
        } catch is CancellationError {
            return
        } catch {
            guard token == catalogGeneration else { return }
            state.phase = .failed(.store)
        }
    }

    /// 責務: 車両のセッション一覧を最新にします。選択が変わっていれば反映しません。
    private func refreshSessionOptions(for vehicleID: VehicleID, token: Int) async throws {
        let found = try await sessions.sessions(for: vehicleID)
        guard token == catalogGeneration, state.selectedVehicleID == vehicleID else { return }
        state.sessionOptions = found.filter { !$0.isRecording }.map(AnalysisSessionOption.init)
    }

    // MARK: - セッションの読み込み

    /// 責務: セッションを開きます。Rawが端末に無ければ、ダウンロードの確認待ちにします。
    private func open(_ id: SessionID, replacing: Bool) async {
        let token = beginOperation()
        if !replacing {
            if state.loadedSessions.contains(where: { $0.id == id }) { return }
            if state.isAtSessionLimit {
                state.phase = .failed(.tooManySessions)
                return
            }
        }
        state.phase = .building(id)
        state.pickerPurpose = nil
        do {
            guard let session = try await sessions.session(id) else { throw AnalysisFailure.sessionNotFound }
            guard token == generation else { return }
            if session.rawAvailability == .cloudOnly {
                pendingDownload = (id, replacing)
                state.phase = .awaitingDownloadConsent(id)
                return
            }
            try await load(session, replacing: replacing, token: token)
        } catch is CancellationError {
            return
        } catch {
            fail(error, token: token)
        }
    }

    /// 責務: 承諾後にiCloudからRawを復元し、続けてセッションを読み込みます。
    private func confirmDownload() async {
        guard let pending = pendingDownload else { return }
        let token = beginOperation()
        pendingDownload = nil
        state.phase = .downloading(pending.id, progress: 0)
        do {
            do {
                try await cloudSync.restoreSessionArchive(pending.id) { [weak self] value in
                    Task { @MainActor [weak self] in self?.updateProgress(value, for: pending.id, token: token) }
                }
            } catch let failure as CloudSyncFailure {
                throw AnalysisFailure.downloadFailed(failure)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw AnalysisFailure.downloadFailed(.other)
            }
            guard token == generation else { return }
            state.phase = .building(pending.id)
            guard let session = try await sessions.session(pending.id) else { throw AnalysisFailure.sessionNotFound }
            guard token == generation else { return }
            try await load(session, replacing: pending.replace, token: token)
        } catch is CancellationError {
            return
        } catch {
            fail(error, token: token)
        }
    }

    /// 責務: ダウンロード中のセッションの進捗を反映します。
    private func updateProgress(_ value: Double, for id: SessionID, token: Int) {
        guard token == generation, case .downloading(let current, _) = state.phase, current == id else { return }
        state.phase = .downloading(id, progress: min(max(value, 0), 1))
    }

    /// 責務: データセットを作成・符号化してストアへ置き、読み込み済み一覧を更新します。
    private func load(_ session: DriveSession, replacing: Bool, token: Int) async throws {
        let dataset = try await buildDataset.build(sessionID: session.id)
        let json = try await AnalysisJSONEncoder.encode(dataset)
        guard token == generation else { return }
        let path = AnalysisDatasetStore.datasetPath(for: session.id)
        store.set(json, forPath: path)
        let loaded = AnalysisLoadedSession(
            id: session.id,
            datasetPath: path,
            vehicleName: dataset.vehicle.name,
            startedAt: session.startedAt,
            isDemo: session.isDemo
        )
        if replacing {
            for old in state.loadedSessions where old.id != session.id { store.remove(path: old.datasetPath) }
            let vehicleChanged = state.selectedVehicleID != session.vehicleID
            state.loadedSessions = [loaded]
            if vehicleChanged { state.trend = .idle }
            state.selectedVehicleID = session.vehicleID
            if state.vehicles.isEmpty || !state.vehicles.contains(where: { $0.id == session.vehicleID }) {
                state.vehicles = try await vehicles.vehicles().map { AnalysisVehicleOption(id: $0.id, name: $0.name) }
            }
            try await refreshSessionOptions(for: session.vehicleID, token: catalogGeneration)
        } else {
            state.loadedSessions.append(loaded)
        }
        guard token == generation else { return }
        state.phase = .ready
        state.contentRevision += 1
    }

    /// 責務: 比較セッションを外します。主セッションは外せません。
    private func removeSession(_ id: SessionID) {
        guard let index = state.loadedSessions.firstIndex(where: { $0.id == id }), index > 0 else { return }
        store.remove(path: state.loadedSessions[index].datasetPath)
        state.loadedSessions.remove(at: index)
        state.contentRevision += 1
    }

    // MARK: - 長期傾向

    /// 責務: 選択中の車両の長期傾向を集計し、ストアへ置きます。
    private func loadTrend(includeDemo: Bool) async {
        let token = beginOperation()
        guard let vehicleID = state.selectedVehicleID else {
            state.phase = .failed(.vehicleNotFound)
            return
        }
        state.trend = .building
        state.phase = .buildingTrend
        do {
            let dataset = try await buildTrend.build(vehicleID: vehicleID, includeDemo: includeDemo)
            let json = try await AnalysisJSONEncoder.encode(dataset)
            guard token == generation else { return }
            store.set(json, forPath: AnalysisDatasetStore.trendPath(for: vehicleID))
            state.trend = .ready(vehicleID)
            state.phase = state.loadedSessions.isEmpty ? .idle : .ready
            state.contentRevision += 1
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            state.trend = .idle
            fail(error, token: token)
        }
    }

    // MARK: - 共通

    /// 責務: 新しい操作の世代を開始し、古い操作の結果を無効にします。
    private func beginOperation() -> Int {
        generation += 1
        return generation
    }

    /// 責務: 失敗を型付きの状態へ反映します。
    private func fail(_ error: Error, token: Int) {
        guard token == generation else { return }
        state.phase = .failed((error as? AnalysisFailure) ?? .store)
    }
}
