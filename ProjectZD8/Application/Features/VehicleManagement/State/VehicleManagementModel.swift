import Foundation
import Observation

/// 車両一覧、編集、写真、削除、PID収集設定を調整します。
@MainActor
@Observable
final class VehicleManagementModel {
    /// 画面が描画する現在状態です。
    private(set) var state = VehicleManagementState()

    @ObservationIgnored private let vehicles: any VehicleRepository
    @ObservationIgnored private let photos: any PhotoRepository
    @ObservationIgnored private let changes: any StoreChangeObserving
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let loadActivity: LoadVehicleActivitySummariesUseCase
    @ObservationIgnored private let loadPIDSettings: LoadVehiclePIDSettingsUseCase
    @ObservationIgnored private let deleteVehicle: DeleteVehicleUseCase
    @ObservationIgnored private let saveEdit: SaveVehicleEditUseCase
    @ObservationIgnored private let pidSettings: any VehiclePIDSettingRepository
    @ObservationIgnored private var observation: Task<Void, Never>?
    /// 読み込み済みの写真を保持します。写真IDの内容は変わらないため無効化は不要です。
    @ObservationIgnored private var photoCache: [PhotoID: Data] = [:]

    /// 永続化契約と時計を注入してモデルを生成します。
    ///
    /// 責務: 車両管理の状態遷移を永続化契約へ結び付けます。
    init(
        vehicles: any VehicleRepository,
        sessions: any SessionRepository,
        pidSettings: any VehiclePIDSettingRepository,
        photos: any PhotoRepository,
        changes: any StoreChangeObserving,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.vehicles = vehicles
        self.photos = photos
        self.pidSettings = pidSettings
        self.changes = changes
        self.now = now
        loadActivity = LoadVehicleActivitySummariesUseCase(sessions: sessions)
        loadPIDSettings = LoadVehiclePIDSettingsUseCase(settings: pidSettings)
        deleteVehicle = DeleteVehicleUseCase(vehicles: vehicles, sessions: sessions)
        saveEdit = SaveVehicleEditUseCase(vehicles: vehicles, photos: photos)
    }

    /// 1件の操作を状態へ反映します。入力のような即時の操作は同期で、永続化を伴う操作は非同期で処理します。
    ///
    /// 責務: 画面からの操作を状態更新または非同期処理へ振り分けます。
    func send(_ action: VehicleManagementAction) {
        switch action {
        case let .draftChanged(draft): changeDraft(draft)
        case .failureDismissed: state.failure = nil
        case .editCancelled: Task { await cancelEditing() }
        case .deleteCancelled: state.pendingDeletion = nil
        case .pidSettingsClosed: state.pidSettings = nil
        case let .pidCategoryFilterChanged(filter): state.pidSettings?.categoryFilter = filter
        case let .pidEnabledFilterChanged(filter): state.pidSettings?.enabledFilter = filter
        case .stopped: stopObserving()
        default: Task { await perform(action) }
        }
    }

    /// 1件の操作を処理し、完了まで待ちます。
    ///
    /// 責務: 全操作の処理本体です。テストと合成はこれを待って結果を確認できます。
    func perform(_ action: VehicleManagementAction) async {
        switch action {
        case .started:
            startObserving()
            state.loadPhase = .loading
            await refresh()
        case .stopped: stopObserving()
        case .refreshRequested: await refresh()
        case let .editRequested(id): await beginEditing(id)
        case let .draftChanged(draft): changeDraft(draft)
        case let .photoPicked(data): await pickPhoto(data)
        case .photoRemoved: await removePhoto()
        case .saveRequested: await save()
        case .editCancelled: await cancelEditing()
        case let .deleteRequested(id): requestDeletion(id)
        case .deleteConfirmed: await confirmDeletion()
        case .deleteCancelled: state.pendingDeletion = nil
        case let .pidSettingsRequested(id): await openPIDSettings(id)
        case .pidSettingsClosed: state.pidSettings = nil
        case let .pidCategoryFilterChanged(filter): state.pidSettings?.categoryFilter = filter
        case let .pidEnabledFilterChanged(filter): state.pidSettings?.enabledFilter = filter
        case let .pidCollectionToggled(request, isEnabled): await toggleCollection(request, isEnabled: isEnabled)
        case .failureDismissed: state.failure = nil
        }
    }

    // MARK: - Observation

    /// 責務: 車両・セッション・写真・PID設定の変更通知を購読して自動で再読み込みします。
    private func startObserving() {
        guard observation == nil else { return }
        let stream = changes.changes(in: [.vehicles, .sessions, .photos, .pidSettings])
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

    /// 責務: 車両一覧と活動集計を読み直し、開いているPID設定画面も更新します。
    private func refresh() async {
        do {
            let stored = try await vehicles.vehicles()
            let activity = try await loadActivity.execute()
            var photoFailed = false
            var items: [VehicleListItem] = []
            for vehicle in stored {
                let data = await photoData(for: vehicle.photoID, didFail: &photoFailed)
                items.append(VehicleListItem(vehicle: vehicle, activity: activity[vehicle.id] ?? VehicleActivitySummary(), photoData: data))
            }
            state.vehicles = items
            state.loadPhase = .loaded
            if photoFailed { state.failure = .photoLoadFailed }
            if let open = state.pidSettings {
                if let vehicle = stored.first(where: { $0.id == open.vehicleID }) {
                    state.pidSettings?.items = try await loadPIDSettings.execute(for: vehicle)
                } else {
                    state.pidSettings = nil
                }
            }
        } catch {
            state.loadPhase = .loaded
            state.failure = .loadFailed
        }
    }

    /// 責務: 写真の画像データをキャッシュ越しに取得します。読めなければ `didFail` を立てます。
    private func photoData(for id: PhotoID?, didFail: inout Bool) async -> Data? {
        guard let id else { return nil }
        if let cached = photoCache[id] { return cached }
        do {
            guard let data = try await photos.imageData(for: id) else { return nil }
            photoCache[id] = data
            return data
        } catch {
            didFail = true
            return nil
        }
    }

    // MARK: - Editing

    /// 責務: 保存済みの車両から編集画面を開きます。
    private func beginEditing(_ id: VehicleID) async {
        guard let item = state.vehicles.first(where: { $0.id == id }) else {
            state.failure = .vehicleNotFound
            return
        }
        let draft = VehicleEditDraft(vehicle: item.vehicle)
        state.editor = VehicleEditorState(
            draft: draft,
            originalPhotoID: item.vehicle.photoID,
            photoData: item.photoData,
            issues: draft.issues(currentYear: currentYear()),
            isSaving: false
        )
    }

    /// 責務: 画面の入力を反映し、動力区分が変わればエネルギー源を整え、検証し直します。
    private func changeDraft(_ draft: VehicleEditDraft) {
        guard var editor = state.editor else { return }
        var next = draft
        if next.powertrain != editor.draft.powertrain {
            next.energySources = VehicleEnergySourcePolicy.normalizedSources(next.energySources, for: next.powertrain)
        }
        editor.draft = next
        editor.issues = next.issues(currentYear: currentYear())
        state.editor = editor
    }

    /// 責務: 選んだ画像を保存し、編集中の写真にします。直前に選んだ未保存の写真は片付けます。
    private func pickPhoto(_ data: Data) async {
        guard let editor = state.editor, !data.isEmpty else { return }
        do {
            let newID = try await photos.save(data, for: editor.draft.vehicleID)
            photoCache[newID] = data
            await discardUnsavedPhoto()
            state.editor?.draft.photoID = newID
            state.editor?.photoData = data
        } catch {
            state.failure = .photoFailed
        }
    }

    /// 責務: 編集中の写真を外します。保存済みの写真は保存時に削除します。
    private func removePhoto() async {
        guard state.editor != nil else { return }
        await discardUnsavedPhoto()
        state.editor?.draft.photoID = nil
        state.editor?.photoData = nil
    }

    /// 責務: この編集中に追加した、まだ車両へ保存していない写真を削除します。
    private func discardUnsavedPhoto() async {
        guard let editor = state.editor, let current = editor.draft.photoID, current != editor.originalPhotoID else { return }
        do { try await photos.delete(current) } catch { state.failure = .photoFailed }
        photoCache[current] = nil
    }

    /// 責務: 編集内容を保存して編集画面を閉じます。
    private func save() async {
        guard let editor = state.editor, !editor.isSaving else { return }
        state.editor?.issues = editor.draft.issues(currentYear: currentYear())
        guard state.editor?.issues.isEmpty == true else {
            state.failure = .invalidInput
            return
        }
        state.editor?.isSaving = true
        do {
            let result = try await saveEdit.execute(
                draft: editor.draft,
                originalPhotoID: editor.originalPhotoID,
                now: now(),
                currentYear: currentYear()
            )
            state.editor = nil
            if result.didFailToDeleteReplacedPhoto { state.failure = .photoFailed }
            await refresh()
        } catch let failure as VehicleManagementFailure {
            state.editor?.isSaving = false
            state.failure = failure
        } catch {
            state.editor?.isSaving = false
            state.failure = .saveFailed
        }
    }

    /// 責務: 保存せず編集画面を閉じ、この編集中に追加した写真を片付けます。
    private func cancelEditing() async {
        await discardUnsavedPhoto()
        state.editor = nil
    }

    /// 責務: 現在の西暦を時計から求めます。
    private func currentYear() -> Int {
        Calendar.current.component(.year, from: now())
    }

    // MARK: - Deletion

    /// 責務: 削除の確認を求めます。記録中の車両は確認へ進めず失敗にします。
    private func requestDeletion(_ id: VehicleID) {
        guard let item = state.vehicles.first(where: { $0.id == id }) else {
            state.failure = .vehicleNotFound
            return
        }
        guard !item.activity.isRecording else {
            state.failure = .deleteRefusedWhileRecording
            return
        }
        state.pendingDeletion = VehicleDeletionPrompt(
            vehicleID: id,
            vehicleName: item.vehicle.name,
            sessionCount: item.activity.sessionCount
        )
    }

    /// 責務: 確認済みの削除を実行します。
    private func confirmDeletion() async {
        guard let prompt = state.pendingDeletion else { return }
        state.pendingDeletion = nil
        do {
            try await deleteVehicle.execute(prompt.vehicleID)
            if state.editor?.draft.vehicleID == prompt.vehicleID { state.editor = nil }
            if state.pidSettings?.vehicleID == prompt.vehicleID { state.pidSettings = nil }
            await refresh()
        } catch let failure as VehicleManagementFailure {
            state.failure = failure
        } catch {
            state.failure = .deleteFailed
        }
    }

    // MARK: - PID settings

    /// 責務: 車両のPID収集設定画面を開きます。
    private func openPIDSettings(_ id: VehicleID) async {
        guard let vehicle = state.vehicles.first(where: { $0.id == id })?.vehicle else {
            state.failure = .vehicleNotFound
            return
        }
        do {
            state.pidSettings = VehiclePIDSettingsState(
                vehicleID: id,
                vehicleName: vehicle.name,
                items: try await loadPIDSettings.execute(for: vehicle)
            )
        } catch {
            state.failure = .pidSettingsFailed
        }
    }

    /// 責務: 1つのPIDの収集有効・無効を保存し、一覧を更新します。応答を確認していないPIDは拒否します。
    private func toggleCollection(_ request: OBDPIDRequest, isEnabled: Bool) async {
        guard let open = state.pidSettings, let item = open.items.first(where: { $0.request == request }) else { return }
        guard item.isSupported else {
            state.failure = .pidNotSupported
            return
        }
        do {
            try await pidSettings.setCollectionEnabled(isEnabled, for: request, vehicleID: open.vehicleID)
            if let index = state.pidSettings?.items.firstIndex(where: { $0.request == request }) {
                state.pidSettings?.items[index] = VehiclePIDSettingItem(
                    request: item.request, nameKey: item.nameKey, unit: item.unit, category: item.category,
                    isVehicleSpecific: item.isVehicleSpecific, support: item.support, isEnabled: isEnabled
                )
            }
        } catch {
            state.failure = .pidSettingsFailed
        }
    }
}
