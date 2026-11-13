import Foundation
import Observation

/// 車両別の整備記録の一覧、編集、写真、削除を調整します。
@MainActor
@Observable
final class MaintenanceModel {
    /// 画面が描画する現在状態です。
    private(set) var state = MaintenanceState()

    @ObservationIgnored private let vehicles: any VehicleRepository
    @ObservationIgnored private let maintenance: any MaintenanceRepository
    @ObservationIgnored private let photos: any PhotoRepository
    @ObservationIgnored private let changes: any StoreChangeObserving
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let saveRecord: SaveMaintenanceRecordUseCase
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var records: [MaintenanceRecord] = []

    /// 永続化契約と時計を注入してモデルを生成します。
    ///
    /// 責務: 整備画面の状態遷移を永続化契約へ結び付けます。
    init(
        vehicles: any VehicleRepository,
        maintenance: any MaintenanceRepository,
        photos: any PhotoRepository,
        changes: any StoreChangeObserving,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.vehicles = vehicles
        self.maintenance = maintenance
        self.photos = photos
        self.changes = changes
        self.now = now
        saveRecord = SaveMaintenanceRecordUseCase(maintenance: maintenance, photos: photos)
    }

    /// 1件の操作を状態へ反映します。入力のような即時の操作は同期で、永続化を伴う操作は非同期で処理します。
    ///
    /// 責務: 画面からの操作を状態更新または非同期処理へ振り分けます。
    func send(_ action: MaintenanceAction) {
        switch action {
        case .started, .refreshRequested, .vehicleSelected, .createRequested, .editRequested, .photoPicked,
             .photoRemoved, .saveRequested, .editCancelled, .deleteConfirmed:
            Task { await perform(action) }
        default:
            applySynchronously(action)
        }
    }

    /// 1件の操作を処理し、完了まで待ちます。
    ///
    /// 責務: 全操作の処理本体です。テストと合成はこれを待って結果を確認できます。
    func perform(_ action: MaintenanceAction) async {
        switch action {
        case .started:
            startObserving()
            state.loadPhase = .loading
            await refresh()
        case .refreshRequested: await refresh()
        case let .vehicleSelected(id):
            state.selectedVehicleID = id
            await refresh()
        case let .createRequested(kind): beginCreation(kind)
        case let .editRequested(id): await beginEditing(id)
        case let .photoPicked(data): await pickPhoto(data)
        case let .photoRemoved(id): await removePhoto(id)
        case .saveRequested: await save()
        case .editCancelled: await cancelEditing()
        case .deleteConfirmed: await confirmDeletion()
        default: applySynchronously(action)
        }
    }

    /// 責務: 永続化を伴わない操作を状態へ反映します。
    private func applySynchronously(_ action: MaintenanceAction) {
        switch action {
        case .stopped: stopObserving()
        case let .kindFilterChanged(kind): state.kindFilter = kind
        case let .draftChanged(draft): editDraft { $0 = draft }
        case .workItemAdded: editDraft { $0.addWorkItem() }
        case let .workItemRemoved(id): editDraft { $0.removeWorkItem(id) }
        case .fastenerGroupAdded: editDraft { $0.addFastenerGroup() }
        case let .fastenerGroupRemoved(id): editDraft { $0.removeFastenerGroup(id) }
        case let .fastenerAdded(groupID): editDraft { $0.addFastener(to: groupID) }
        case let .fastenerRemoved(groupID, evidenceID): editDraft { $0.removeFastener(groupID: groupID, evidenceID: evidenceID) }
        case let .fastenerConfirmed(groupID, evidenceID):
            let date = now()
            editDraft { $0.confirmFastener(groupID: groupID, evidenceID: evidenceID, at: date) }
        case let .fastenerPhotoLinked(groupID, evidenceID, photoID):
            editDraft { $0.linkPhoto(photoID, groupID: groupID, evidenceID: evidenceID) }
        case let .fastenerPhotoUnlinked(groupID, evidenceID, photoID):
            editDraft { $0.unlinkPhoto(photoID, groupID: groupID, evidenceID: evidenceID) }
        case let .removalPhotoLinked(groupID, photoID): editDraft { $0.linkRemovalPhoto(photoID, groupID: groupID) }
        case let .removalPhotoUnlinked(groupID, photoID): editDraft { $0.unlinkRemovalPhoto(photoID, groupID: groupID) }
        case let .photoCaptionChanged(id, caption): editDraft { $0.setCaption(caption, for: id) }
        case let .deleteRequested(id): requestDeletion(id)
        case .deleteCancelled: state.pendingDeletion = nil
        case .failureDismissed: state.failure = nil
        default: break
        }
    }

    // MARK: - Observation

    /// 責務: 車両・整備・写真の変更通知を購読して自動で再読み込みします。
    private func startObserving() {
        guard observation == nil else { return }
        let stream = changes.changes(in: [.vehicles, .maintenance, .photos])
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

    /// 責務: 車両の選択肢と、選択車両の整備記録を読み直します。編集中の入力には触れません。
    private func refresh() async {
        do {
            let stored = try await vehicles.vehicles()
            state.vehicles = stored.map { MaintenanceVehicleOption(id: $0.id, name: $0.name) }
            if !stored.contains(where: { $0.id == state.selectedVehicleID }) {
                state.selectedVehicleID = stored.first?.id
            }
            if let selected = state.selectedVehicleID {
                records = try await maintenance.records(for: selected).sorted { $0.performedAt > $1.performedAt }
            } else {
                records = []
            }
            state.rows = records.map(MaintenanceListRow.init(record:))
            state.loadPhase = .loaded
        } catch {
            state.loadPhase = .loaded
            state.failure = .loadFailed
        }
    }

    // MARK: - Editing

    /// 責務: 選択車両の新規入力を開きます。
    private func beginCreation(_ kind: MaintenanceKind) {
        guard let vehicleID = state.selectedVehicleID else {
            state.failure = .vehicleRequired
            return
        }
        let draft = MaintenanceDraft(vehicleID: vehicleID, kind: kind, now: now())
        state.editor = MaintenanceEditorState(draft: draft, originalPhotoIDs: [], photoData: [:], issues: draft.issues(), isSaving: false)
    }

    /// 責務: 保存済みの記録を編集入力として開き、写真の画像データを読み込みます。
    private func beginEditing(_ id: MaintenanceRecordID) async {
        guard let record = records.first(where: { $0.id == id }) else {
            state.failure = .recordNotFound
            return
        }
        let draft = MaintenanceDraft(record: record)
        var data: [PhotoID: Data] = [:]
        var didFail = false
        for photo in record.photos {
            do {
                if let bytes = try await photos.imageData(for: photo.id) { data[photo.id] = bytes }
            } catch {
                didFail = true
            }
        }
        state.editor = MaintenanceEditorState(
            draft: draft,
            originalPhotoIDs: Set(record.photos.map(\.id)),
            photoData: data,
            issues: draft.issues(),
            isSaving: false
        )
        if didFail { state.failure = .photoLoadFailed }
    }

    /// 責務: 開いている入力へ変更を加え、検証し直します。
    private func editDraft(_ change: (inout MaintenanceDraft) -> Void) {
        guard var editor = state.editor else { return }
        change(&editor.draft)
        editor.issues = editor.draft.issues()
        state.editor = editor
    }

    /// 責務: 選んだ画像を車両の写真として保存し、入力へ追加します。
    private func pickPhoto(_ data: Data) async {
        guard let editor = state.editor, !data.isEmpty else { return }
        do {
            let id = try await photos.save(data, for: editor.draft.vehicleID)
            guard state.editor != nil else {
                try? await photos.delete(id)
                return
            }
            state.editor?.photoData[id] = data
            editDraft { $0.addPhoto(MaintenancePhoto(id: id, capturedAt: now())) }
        } catch {
            state.failure = .photoFailed
        }
    }

    /// 責務: 写真を入力から外します。この編集中に追加した写真はすぐ削除し、保存済みの写真は保存時に削除します。
    private func removePhoto(_ id: PhotoID) async {
        guard let editor = state.editor, editor.draft.photos.contains(where: { $0.id == id }) else { return }
        editDraft { $0.removePhoto(id) }
        state.editor?.photoData[id] = nil
        if !editor.originalPhotoIDs.contains(id) {
            do { try await photos.delete(id) } catch { state.failure = .photoFailed }
        }
    }

    /// 責務: 入力を保存して編集画面を閉じます。
    private func save() async {
        guard let editor = state.editor, !editor.isSaving else { return }
        state.editor?.issues = editor.draft.issues()
        guard state.editor?.issues.isEmpty == true else {
            state.failure = .invalidInput
            return
        }
        state.editor?.isSaving = true
        do {
            let result = try await saveRecord.execute(draft: editor.draft, originalPhotoIDs: editor.originalPhotoIDs, now: now())
            state.editor = nil
            if result.didFailToDeletePhotos { state.failure = .photoFailed }
            await refresh()
        } catch let failure as MaintenanceFailure {
            state.editor?.isSaving = false
            state.failure = failure
        } catch {
            state.editor?.isSaving = false
            state.failure = .saveFailed
        }
    }

    /// 責務: 保存せず編集画面を閉じ、この編集中に追加した写真を削除します。
    private func cancelEditing() async {
        guard let editor = state.editor else { return }
        state.editor = nil
        for photo in editor.draft.photos where !editor.originalPhotoIDs.contains(photo.id) {
            do { try await photos.delete(photo.id) } catch { state.failure = .photoFailed }
        }
    }

    // MARK: - Deletion

    /// 責務: 削除の確認を求めます。
    private func requestDeletion(_ id: MaintenanceRecordID) {
        guard let record = records.first(where: { $0.id == id }) else {
            state.failure = .recordNotFound
            return
        }
        state.pendingDeletion = MaintenanceDeletionPrompt(recordID: id, title: record.title, photoCount: record.photos.count)
    }

    /// 責務: 確認済みの削除を実行します。
    private func confirmDeletion() async {
        guard let prompt = state.pendingDeletion else { return }
        state.pendingDeletion = nil
        do {
            try await maintenance.delete(prompt.recordID)
            if state.editor?.draft.recordID == prompt.recordID { state.editor = nil }
            await refresh()
        } catch {
            state.failure = .deleteFailed
        }
    }
}
