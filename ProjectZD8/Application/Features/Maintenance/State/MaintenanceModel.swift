import Foundation
import Observation

/// 車両別整備の一覧、編集、GRDB保存、CloudKit同期を調整します。
@MainActor
@Observable
final class MaintenanceModel {
    /// Platformが描画する現在状態です。
    var state: MaintenanceState
    /// 端末内の整備記録保存先です。
    @ObservationIgnored private let repository: any MaintenanceRecordRepository
    /// GRDBとCloudKitを双方向統合するユースケースです。
    @ObservationIgnored private let synchronize: SynchronizeMaintenanceRecordsUseCase
    /// ユーザー選択写真の読込境界です。
    @ObservationIgnored private let photoImporter: any MaintenancePhotoImportPort
    /// 更新日時をテスト可能に生成する処理です。
    @ObservationIgnored private let now: @Sendable () -> Date
    /// 現在の整備記録を所有するAppleアカウント識別子です。
    @ObservationIgnored private var accountIdentifier: String?

    /// 状態と整備保存・同期境界を注入してモデルを生成します。
    ///
    /// 責務: 整備画面状態を端末内保存、遠隔同期、写真読込へ結び付けます。
    /// - Parameters:
    ///   - state: 初期表示状態。
    ///   - repository: 端末内の整備記録保存先。
    ///   - synchronize: 双方向同期ユースケース。
    ///   - photoImporter: 選択写真の読込境界。
    ///   - now: 作成、更新、削除日時の生成処理。
    init(
        state: MaintenanceState,
        repository: any MaintenanceRecordRepository,
        synchronize: SynchronizeMaintenanceRecordsUseCase,
        photoImporter: any MaintenancePhotoImportPort,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.state = state
        self.repository = repository
        self.synchronize = synchronize
        self.photoImporter = photoImporter
        self.now = now
    }

    /// 1件の型付き操作を整備状態と副作用へ反映します。
    ///
    /// 責務: 整備操作を対応する状態更新または非同期ワークフロー1件へ振り分けます。
    /// - Parameter action: PlatformまたはAppから通知された操作。
    func send(_ action: MaintenanceAction) {
        switch action {
        case let .accountIdentifierChanged(identifier): activateAccount(identifier)
        case let .vehiclesChanged(vehicles): updateVehicles(vehicles)
        case let .vehicleSelected(id): state.selectedVehicleID = id
        case let .kindFilterChanged(kind): state.kindFilter = kind
        case let .createRequested(kind): beginCreation(kind: kind)
        case let .editRequested(id): beginEditing(id: id)
        case let .draftChanged(draft): state.draft = draft
        case .workItemAdded: addWorkItem()
        case let .workItemRemoved(id): state.draft?.workItems.removeAll { $0.id == id }
        case .fastenerGroupAdded: addFastenerGroup()
        case let .fastenerAdded(groupID): addFastener(to: groupID)
        case let .fastenerConfirmed(groupID, evidenceID): confirmFastener(groupID: groupID, evidenceID: evidenceID)
        case let .latestPhotoLinked(groupID, evidenceID): linkLatestPhoto(groupID: groupID, evidenceID: evidenceID)
        case let .fastenerGroupRemoved(id): state.draft?.fastenerGroups.removeAll { $0.id == id }
        case let .photoSelected(url): Task { await importPhoto(at: url) }
        case let .photoRemoved(id): state.draft?.photos.removeAll { $0.id == id }
        case .saveRequested: Task { await saveDraft() }
        case .editingCancelled: finishEditing()
        case let .deleteRequested(id): Task { await deleteRecord(id: id) }
        case .refreshRequested: Task { await synchronizeRecords() }
        }
    }

    /// 認証アカウント変更時に状態を初期化してローカル読込と同期を開始します。
    ///
    /// 責務: 1件の認証識別子変更を整備スコープの解除または読込開始へ変換します。
    /// - Parameter identifier: 新しいAppleアカウント識別子。
    private func activateAccount(_ identifier: String?) {
        guard identifier != accountIdentifier else { return }
        accountIdentifier = identifier
        let vehicles = state.vehicles
        state = MaintenanceState(vehicles: vehicles, selectedVehicleID: vehicles.first?.id)
        guard identifier?.isEmpty == false else { return }
        Task { await loadLocalThenSynchronize() }
    }

    /// Garage由来の登録車両集合を整備対象選択へ反映します。
    ///
    /// 責務: 現在の車両集合を保持し無効な選択だけを先頭車両へ修正します。
    /// - Parameter vehicles: 現在のアカウントに属する登録車両。
    private func updateVehicles(_ vehicles: [VehicleProfile]) {
        state.vehicles = vehicles
        if let selected = state.selectedVehicleID, vehicles.contains(where: { $0.id == selected }) {
            return
        }
        state.selectedVehicleID = vehicles.first?.id
    }

    /// 選択車両へ新規整備入力を作成します。
    ///
    /// 責務: 1件の整備区分を現在車両へ必須関連付けした編集入力へ変換します。
    /// - Parameter kind: 開始する軽整備または重整備。
    private func beginCreation(kind: MaintenanceKind) {
        guard let vehicleID = state.selectedVehicleID else {
            state.failureKey = "maintenance.error.vehicle_required"
            return
        }
        state.draft = MaintenanceEditorDraft(vehicleID: vehicleID, kind: kind, now: now())
        state.phase = .editing
        state.failureKey = nil
        addWorkItem()
    }

    /// 保存済み整備記録を編集入力へ変換します。
    ///
    /// 責務: 指定IDの1件を見つけて編集段階へ移行します。
    /// - Parameter id: 編集する整備記録ID。
    private func beginEditing(id: MaintenanceRecordID) {
        guard let record = state.records.first(where: { $0.id == id }) else { return }
        state.draft = MaintenanceEditorDraft(record: record)
        state.phase = .editing
        state.failureKey = nil
    }

    /// 編集中区分に適した初期作業項目を追加します。
    ///
    /// 責務: 現在の入力へ軽整備または重整備の既定作業項目を1件追加します。
    private func addWorkItem() {
        guard var draft = state.draft else { return }
        let item = MaintenanceWorkItem(
            component: draft.kind == .light ? .engineOil : .engineAssembly,
            operation: draft.kind == .light ? .replacement : .inspection
        )
        draft.workItems.append(item)
        state.draft = draft
    }

    /// 重整備入力へ可変本数の締結グループを追加します。
    ///
    /// 責務: 現在の重整備入力へ空の分解・締結追跡単位を1件追加します。
    private func addFastenerGroup() {
        guard var draft = state.draft, draft.kind == .heavy else { return }
        draft.fastenerGroups.append(MaintenanceFastenerGroup(name: ""))
        state.draft = draft
    }

    /// 指定締結グループへ個別位置を追加します。
    ///
    /// 責務: 1件の締結グループへ追跡可能な個別締結証跡を追加します。
    /// - Parameter groupID: 追加先の締結グループID。
    private func addFastener(to groupID: UUID) {
        guard var draft = state.draft,
              let index = draft.fastenerGroups.firstIndex(where: { $0.id == groupID }) else { return }
        draft.fastenerGroups[index].installations.append(FastenerInstallationEvidence(position: ""))
        state.draft = draft
    }

    /// 個別締結へApplicationが生成した完了日時を記録します。
    ///
    /// 責務: 指定した1本の締結証跡へ現在の完了日時を設定します。
    /// - Parameters:
    ///   - groupID: 締結グループID。
    ///   - evidenceID: 個別締結証跡ID。
    private func confirmFastener(groupID: UUID, evidenceID: UUID) {
        guard var draft = state.draft,
              let groupIndex = draft.fastenerGroups.firstIndex(where: { $0.id == groupID }),
              let evidenceIndex = draft.fastenerGroups[groupIndex].installations.firstIndex(where: { $0.id == evidenceID }) else { return }
        draft.fastenerGroups[groupIndex].installations[evidenceIndex].tightenedAt = now()
        state.draft = draft
    }

    /// 最新の作業写真を個別締結証跡へ関連付けます。
    ///
    /// 責務: 現在入力の最新写真IDを指定した1本の締結証跡へ重複なく追加します。
    /// - Parameters:
    ///   - groupID: 締結グループID。
    ///   - evidenceID: 個別締結証跡ID。
    private func linkLatestPhoto(groupID: UUID, evidenceID: UUID) {
        guard var draft = state.draft, let photoID = draft.photos.last?.id,
              let groupIndex = draft.fastenerGroups.firstIndex(where: { $0.id == groupID }),
              let evidenceIndex = draft.fastenerGroups[groupIndex].installations.firstIndex(where: { $0.id == evidenceID }) else { return }
        if !draft.fastenerGroups[groupIndex].installations[evidenceIndex].photoIDs.contains(photoID) {
            draft.fastenerGroups[groupIndex].installations[evidenceIndex].photoIDs.append(photoID)
        }
        state.draft = draft
    }

    /// 選択写真を現在の編集入力へ追加します。
    ///
    /// 責務: 1件の選択URLを読み込み追跡可能な写真エビデンスへ変換します。
    /// - Parameter url: Platformのファイル選択で得たURL。
    private func importPhoto(at url: URL) async {
        guard state.draft != nil else { return }
        do {
            let data = try await photoImporter.importPhoto(at: url)
            guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            state.draft?.photos.append(MaintenancePhoto(data: data, capturedAt: now()))
            state.failureKey = nil
        } catch {
            state.failureKey = "maintenance.error.photo"
        }
    }

    /// 現在の編集入力を車両別Domain記録として保存します。
    ///
    /// 責務: 1件の有効な整備入力をローカル保存しCloudKit同期へ進めます。
    private func saveDraft() async {
        guard let accountIdentifier, let draft = state.draft else { return }
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !draft.workItems.isEmpty else {
            state.failureKey = "maintenance.error.required"
            return
        }
        state.phase = .saving
        let timestamp = now()
        let record = MaintenanceRecord(
            id: draft.recordID ?? MaintenanceRecordID(),
            vehicleID: draft.vehicleID,
            kind: draft.kind,
            title: trimmedTitle,
            performedAt: draft.performedAt,
            odometerKilometers: draft.odometerKilometers,
            notes: draft.notes,
            workItems: draft.workItems,
            photos: draft.photos,
            fastenerGroups: draft.kind == .heavy ? draft.fastenerGroups : [],
            createdAt: draft.createdAt,
            updatedAt: timestamp
        )
        do {
            try await repository.save(record, for: accountIdentifier)
            state.draft = nil
            await synchronizeRecords()
        } catch {
            state.phase = .failed
            state.failureKey = "maintenance.error.save"
        }
    }

    /// 指定記録を削除墓石へ変換して全端末へ同期します。
    ///
    /// 責務: 1件の整備記録へ削除日時を設定しローカル保存後に同期します。
    /// - Parameter id: 削除する整備記録ID。
    private func deleteRecord(id: MaintenanceRecordID) async {
        guard let accountIdentifier,
              var record = state.records.first(where: { $0.id == id }) else { return }
        let timestamp = now()
        record.deletedAt = timestamp
        record.updatedAt = timestamp
        do {
            try await repository.save(record, for: accountIdentifier)
            state.draft = nil
            await synchronizeRecords()
        } catch {
            state.phase = .failed
            state.failureKey = "maintenance.error.delete"
        }
    }

    /// 編集入力を破棄して一覧へ戻ります。
    ///
    /// 責務: 現在の未保存入力だけを破棄し整備一覧を再表示します。
    private func finishEditing() {
        state.draft = nil
        state.phase = .idle
        state.failureKey = nil
    }

    /// ローカル記録を先に表示してからCloudKit双方向同期を実行します。
    ///
    /// 責務: 1件のアカウントについてオフライン表示を確保した後に遠隔同期します。
    private func loadLocalThenSynchronize() async {
        guard let accountIdentifier else { return }
        state.phase = .syncing
        do {
            state.records = try await repository.records(for: accountIdentifier)
                .filter { $0.deletedAt == nil }
                .sorted { $0.performedAt > $1.performedAt }
        } catch {
            state.phase = .failed
            state.failureKey = "maintenance.error.load"
            return
        }
        await synchronizeRecords()
    }

    /// 現在アカウントのローカル記録とCloudKit記録を同期します。
    ///
    /// 責務: 1件のアカウントに対する同期結果を一覧と同期状態へ反映します。
    private func synchronizeRecords() async {
        guard let accountIdentifier else { return }
        state.phase = .syncing
        do {
            state.records = try await synchronize.execute(accountIdentifier: accountIdentifier)
            state.lastSynchronizedAt = now()
            state.phase = .idle
            state.failureKey = nil
        } catch {
            state.records = ((try? await repository.records(for: accountIdentifier)) ?? [])
                .filter { $0.deletedAt == nil }
                .sorted { $0.performedAt > $1.performedAt }
            state.phase = .failed
            state.failureKey = "maintenance.error.sync"
        }
    }
}
