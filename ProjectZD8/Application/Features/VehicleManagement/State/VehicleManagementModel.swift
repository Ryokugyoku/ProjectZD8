import Foundation
import Observation

/// 車両一覧、OBD識別確認、登録編集を永続化とOBD識別へ結び付けます。
@MainActor
@Observable
final class VehicleManagementModel {
    /// Platformが描画する現在状態です。
    var state: VehicleManagementState
    /// 車両の読込、保存、削除を行う永続化境界です。
    @ObservationIgnored private let repository: any VehicleRepository
    /// 接続操作を同種の車両識別子照合へ変換するユースケースです。
    @ObservationIgnored private let identifyForConnection: IdentifyVehicleForConnectionUseCase
    /// ユーザーが選択した画像を読み込む境界です。
    @ObservationIgnored private let photoImporter: any VehiclePhotoImportPort
    /// 車両別対応PID設定の永続化境界です。
    @ObservationIgnored private let pidCapabilityRepository: (any VehiclePIDCapabilityRepository)?
    /// PID名称を解決するカタログ境界です。
    @ObservationIgnored private let pidDefinitionRepository: (any OBDPIDDefinitionRepository)?
    /// 接続対象車両、終端、編集前のOBD識別観測をLoggingと監視開始へ通知する処理です。
    @ObservationIgnored private let connectionVehicleDidResolve: @MainActor (
        VehicleProfile,
        OBDConnectionEndpoint,
        VehicleIdentificationSnapshot
    ) -> Void
    /// 現在の車両を所有するAppleアカウント識別子です。
    @ObservationIgnored private var accountIdentifier: String?

    /// 初期状態、注入済み境界、車両確定通知先を使ってモデルを生成します。
    ///
    /// 責務: 車両管理状態を永続化、OBD識別、画像取込の各境界へ結び付けます。
    /// - Parameters:
    ///   - state: 初期表示状態。
    ///   - repository: アカウントスコープ付き車両保存先。
    ///   - identifyForConnection: VINまたは非VIN識別子の取得と登録照合を行うユースケース。
    ///   - photoImporter: 選択画像をプロフィールデータへ変換する境界。
    ///   - pidCapabilityRepository: 車両別対応PID設定の保存先。
    ///   - pidDefinitionRepository: PID名称を解決するカタログ境界。
    ///   - connectionVehicleDidResolve: 接続対象車両、終端、編集前のOBD識別観測を通知する処理。
    init(
        state: VehicleManagementState,
        repository: any VehicleRepository,
        identifyForConnection: IdentifyVehicleForConnectionUseCase,
        photoImporter: any VehiclePhotoImportPort,
        pidCapabilityRepository: (any VehiclePIDCapabilityRepository)? = nil,
        pidDefinitionRepository: (any OBDPIDDefinitionRepository)? = nil,
        connectionVehicleDidResolve: @escaping @MainActor (
            VehicleProfile,
            OBDConnectionEndpoint,
            VehicleIdentificationSnapshot
        ) -> Void = { _, _, _ in }
    ) {
        self.state = state
        self.repository = repository
        self.identifyForConnection = identifyForConnection
        self.photoImporter = photoImporter
        self.pidCapabilityRepository = pidCapabilityRepository
        self.pidDefinitionRepository = pidDefinitionRepository
        self.connectionVehicleDidResolve = connectionVehicleDidResolve
    }

    /// 1件の型付き操作を車両管理状態と副作用へ反映します。
    ///
    /// 責務: 車両管理操作を対応する非同期ワークフロー1件へ振り分けます。
    /// - Parameter action: PlatformまたはAppから通知された操作。
    func send(_ action: VehicleManagementAction) {
        switch action {
        case let .accountIdentifierChanged(identifier): activateAccount(identifier)
        case let .identifyRequested(endpoint): Task { await identifyVehicle(using: endpoint) }
        case .identificationRetryRequested:
            if let endpoint = state.connectionEndpoint { Task { await identifyVehicle(using: endpoint) } }
        case .identificationConfirmed: beginRegistration()
        case .registrationCancelled: cancelRegistration()
        case let .vehicleSaved(vehicle): Task { await save(vehicle) }
        case let .editRequested(id): beginEditing(id)
        case .editCancelled: finishEditing()
        case let .photoSelected(url): Task { await importPhoto(at: url) }
        case let .vehicleDeleted(id): Task { await delete(id) }
        case .refreshRequested: Task { await loadVehicles() }
        case let .pidSettingsRequested(vehicleID): loadPIDSettings(for: vehicleID)
        case let .pidCollectionChanged(request, isEnabled): updatePIDSelection(request, isEnabled: isEnabled)
        case .pidSettingsClosed:
            state.pidSettingsVehicleID = nil
            state.pidSelectionItems = []
        }
    }

    /// 指定車両の対応PIDと名称を収集設定状態へ読み込みます。
    ///
    /// 責務: 1件の車両IDをPIDテーブル名称付き収集選択一覧へ変換します。
    /// - Parameter vehicleID: 設定対象のアプリ内車両ID。
    private func loadPIDSettings(for vehicleID: VehicleID) {
        guard let pidCapabilityRepository, let pidDefinitionRepository else {
            state.failureKey = "garage.pid_settings.error"
            return
        }
        do {
            let definitions = try pidDefinitionRepository.definitions()
            let names = Dictionary(uniqueKeysWithValues: definitions.map {
                (OBDPIDRequest(service: $0.service, pid: $0.pid), $0.nameKey)
            })
            state.pidSelectionItems = try pidCapabilityRepository.capabilities(for: vehicleID).map {
                VehiclePIDSelectionItem(id: $0.id.request, nameKey: names[$0.id.request], isEnabled: $0.isCollectionEnabled)
            }
            state.pidSettingsVehicleID = vehicleID
            state.failureKey = nil
        } catch {
            state.failureKey = "garage.pid_settings.error"
        }
    }

    /// 現在表示中の車両で1件のPID収集選択を更新します。
    ///
    /// 責務: 1件のPID選択操作を永続化して現在表示へ反映します。
    /// - Parameters:
    ///   - request: 更新するService/PID。
    ///   - isEnabled: 新しい収集有効状態。
    private func updatePIDSelection(_ request: OBDPIDRequest, isEnabled: Bool) {
        guard let vehicleID = state.pidSettingsVehicleID, let pidCapabilityRepository else { return }
        do {
            try pidCapabilityRepository.setCollectionEnabled(isEnabled, for: request, vehicleID: vehicleID)
            if let index = state.pidSelectionItems.firstIndex(where: { $0.id == request }) {
                state.pidSelectionItems[index].isEnabled = isEnabled
            }
        } catch {
            state.failureKey = "garage.pid_settings.error"
        }
    }

    /// 新しいアカウントスコープを有効化または解除します。
    ///
    /// 責務: 1件の認証識別子変更を車両状態の初期化と再読込へ反映します。
    /// - Parameter identifier: 新しいAppleアカウント識別子。
    private func activateAccount(_ identifier: String?) {
        guard identifier != accountIdentifier else { return }
        accountIdentifier = identifier
        state = VehicleManagementState()
        guard identifier?.isEmpty == false else { return }
        Task { await loadVehicles() }
    }

    /// 現在アカウントの車両一覧を同期先またはキャッシュから読み込みます。
    ///
    /// 責務: 現在の1件のアカウントスコープへ車両一覧読込結果を反映し、更新日時ベースで同期待ち合わせします。
    private func loadVehicles() async {
        guard let accountIdentifier else { return }
        state.phase = .loading
        do {
            let remote = try await repository.loadVehicles(for: accountIdentifier)
            let syncResult = reconcileVehicles(local: state.vehicles, remote: remote)
            state.vehicles = syncResult.merged
            state.hasLoadedVehicles = true
            state.phase = .idle
            state.failureKey = nil
            Task { [accountIdentifier] in
                for vehicle in syncResult.uploadTargets {
                    try? await repository.saveVehicle(vehicle, for: accountIdentifier)
                }
            }
        } catch {
            state.phase = .failed
            state.failureKey = "garage.error.sync"
        }
    }

    /// ローカルとキャッシュ読込データを更新日時で突合し、同期方針を作成します。
    ///
    /// 責務: 1回の読込結果をローカル一覧と比較し、採用対象とクラウド反映候補を返します。
    /// - Parameters:
    ///   - local: 画面保持中の車両一覧。
    ///   - remote: リポジトリ読込時点の車両一覧。
    /// - Returns: 反映先一覧とアップロード対象。
    private func reconcileVehicles(
        local: [VehicleProfile],
        remote: [VehicleProfile]
    ) -> (merged: [VehicleProfile], uploadTargets: [VehicleProfile]) {
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        var merged: [VehicleProfile] = []
        var uploadTargets: [VehicleProfile] = []
        var syncedIDs: Set<VehicleID> = []

        for localVehicle in local {
            if let remoteVehicle = remoteByID[localVehicle.id] {
                syncedIDs.insert(localVehicle.id)
                if localVehicle.updatedAt > remoteVehicle.updatedAt {
                    merged.append(localVehicle)
                    uploadTargets.append(localVehicle)
                } else {
                    merged.append(remoteVehicle)
                }
            } else {
                merged.append(localVehicle)
                uploadTargets.append(localVehicle)
            }
        }

        for remoteVehicle in remote where !syncedIDs.contains(remoteVehicle.id) {
            merged.append(remoteVehicle)
        }

        return (merged.sorted { $0.updatedAt > $1.updatedAt }, uploadTargets)
    }

    /// OBD識別結果を登録済み接続または登録確認へ反映します。
    ///
    /// 責務: 1回のHOME接続要求を車両識別子の照合結果に応じた状態へ進めます。
    /// - Parameter endpoint: 接続するOBDアダプターの物理終端。
    private func identifyVehicle(using endpoint: OBDConnectionEndpoint) async {
        guard accountIdentifier != nil, state.phase != .identifying else { return }
        state.connectionEndpoint = endpoint
        state.phase = .identifying
        state.failureKey = nil
        state.identificationFailureStage = nil
        do {
            switch try await identifyForConnection.execute(endpoint: endpoint, vehicles: state.vehicles) {
            case let .registered(vehicle, snapshot):
                state.connectionVehicle = vehicle
                state.phase = .readyToConnect
                connectionVehicleDidResolve(vehicle, endpoint, snapshot)
            case let .requiresRegistration(snapshot):
                state.pendingIdentification = snapshot
                state.phase = .confirmingIdentification
            }
        } catch VehicleIdentificationError.stageFailed(let stage, let cause) {
            applyIdentificationFailure(stage: stage, cause: cause)
        } catch VehicleIdentificationError.vinUnavailable {
            state.phase = .failed
            state.failureKey = "garage.error.vin_unavailable"
        } catch VehicleIdentificationError.pidCatalogUnavailable {
            state.phase = .failed
            state.failureKey = "garage.error.pid_catalog"
        } catch VehicleIdentificationError.connectionFailed {
            state.phase = .failed
            state.failureKey = "garage.error.connection"
        } catch VehicleIdentificationError.responseTimedOut {
            state.phase = .failed
            state.failureKey = "garage.error.timeout"
        } catch VehicleIdentificationError.commandRejected {
            state.phase = .failed
            state.failureKey = "garage.error.command_rejected"
        } catch VehicleIdentificationError.malformedResponse {
            state.phase = .failed
            state.failureKey = "garage.error.malformed_response"
        } catch {
            state.phase = .failed
            state.failureKey = "garage.error.obd_unavailable"
        }
    }

    /// 型付き識別失敗をmacOSとiOSが描画できる段階と原因文言へ反映します。
    ///
    /// 責務: 1件の車両識別失敗を失敗状態、段階、原因ローカライズキーへ変換します。
    /// - Parameters:
    ///   - stage: 完了できなかった車両識別段階。
    ///   - cause: その段階で観測した単一原因。
    private func applyIdentificationFailure(
        stage: VehicleIdentificationError.Stage,
        cause: VehicleIdentificationError.Cause
    ) {
        state.phase = .failed
        state.identificationFailureStage = stage
        switch cause {
        case .unavailable, .transportUnsupported:
            state.failureKey = "garage.error.obd_unavailable"
        case .connectionFailed:
            state.failureKey = "garage.error.connection"
        case .responseTimedOut:
            state.failureKey = "garage.error.timeout"
        case .commandRejected:
            state.failureKey = "garage.error.command_rejected"
        case .malformedResponse:
            state.failureKey = "garage.error.malformed_response"
        }
    }

    /// 確認済みOBD識別子から新規プロフィール入力を開始します。
    ///
    /// 責務: 保持中のVINまたは非VIN識別観測1件を編集可能な新規プロフィールへ変換します。
    private func beginRegistration() {
        guard let snapshot = state.pendingIdentification,
              snapshot.vin != nil || snapshot.obdIdentifier != nil else { return }
        let manufacturer = snapshot.fields.first(where: { $0.id == "manufacturer" })?.value ?? ""
        let engineModel = snapshot.fields.first(where: { $0.id == "engineModel" })?.value ?? ""
        state.editingVehicle = VehicleProfile(
            vin: snapshot.vin ?? "",
            obdIdentifier: snapshot.obdIdentifier,
            name: manufacturer.isEmpty ? "" : manufacturer,
            manufacturer: manufacturer,
            engineModel: engineModel,
            isDefault: state.vehicles.isEmpty
        )
        state.phase = .registering
    }

    /// 未完了の新規登録を破棄して一覧へ戻ります。
    ///
    /// 責務: 新規登録用の観測と編集値だけを現在状態から解除します。
    private func cancelRegistration() {
        state.pendingIdentification = nil
        state.editingVehicle = nil
        state.phase = .idle
    }

    /// 指定車両のプロフィール編集を開始します。
    ///
    /// 責務: 登録一覧から指定IDの車両1件を編集状態へ設定します。
    /// - Parameter id: 編集対象のアプリ内車両ID。
    private func beginEditing(_ id: VehicleID) {
        guard let vehicle = state.vehicles.first(where: { $0.id == id }) else { return }
        state.editingVehicle = vehicle
        state.phase = .editing
    }

    /// 現在のプロフィール編集を保存せず終了します。
    ///
    /// 責務: 編集対象1件を解除して車両一覧表示へ戻します。
    private func finishEditing() {
        state.editingVehicle = nil
        state.phase = .idle
    }

    /// 選択画像を現在の編集プロフィールへ反映します。
    ///
    /// 責務: 1件のファイル選択結果を編集中車両の写真データへ変換します。
    /// - Parameter url: Platformが選択した画像URL。
    private func importPhoto(at url: URL) async {
        guard var vehicle = state.editingVehicle else { return }
        do {
            vehicle.photoData = try await photoImporter.importPhoto(at: url)
            state.editingVehicle = vehicle
            state.failureKey = nil
        } catch {
            state.failureKey = "garage.error.photo"
        }
    }

    /// 1件のプロフィールを現在アカウントへ保存します。
    ///
    /// 責務: 編集済み車両1件を保存し最新一覧へ置き換えます。
    /// - Parameter vehicle: 保存する編集済みプロフィール。
    private func save(_ vehicle: VehicleProfile) async {
        guard let accountIdentifier else { return }
        let connectionIdentification = state.phase == .registering ? state.pendingIdentification : nil
        var saved = vehicle
        saved.updatedAt = Date()
        if saved.isDefault {
            for index in state.vehicles.indices where state.vehicles[index].id != saved.id {
                state.vehicles[index].isDefault = false
                try? await repository.saveVehicle(state.vehicles[index], for: accountIdentifier)
            }
        }
        do {
            try await repository.saveVehicle(saved, for: accountIdentifier)
            if let index = state.vehicles.firstIndex(where: { $0.id == saved.id }) {
                state.vehicles[index] = saved
            } else {
                state.vehicles.append(saved)
            }
            state.vehicles.sort { $0.updatedAt > $1.updatedAt }
            state.editingVehicle = nil
            state.pendingIdentification = nil
            if let connectionIdentification {
                state.connectionVehicle = saved
                if let endpoint = state.connectionEndpoint {
                    connectionVehicleDidResolve(saved, endpoint, connectionIdentification)
                }
            }
            state.phase = .idle
            state.failureKey = nil
        } catch {
            state.vehicles = (try? await repository.loadVehicles(for: accountIdentifier)) ?? state.vehicles
            state.phase = .failed
            state.failureKey = "garage.error.save"
        }
    }

    /// 指定車両を現在アカウントから削除します。
    ///
    /// 責務: 指定IDの車両1件を保存先と表示一覧の両方から除去します。
    /// - Parameter id: 削除対象のアプリ内車両ID。
    private func delete(_ id: VehicleID) async {
        guard let accountIdentifier else { return }
        do {
            try await repository.deleteVehicle(id: id, for: accountIdentifier)
            state.vehicles.removeAll { $0.id == id }
            state.editingVehicle = nil
            state.phase = .idle
        } catch {
            state.phase = .failed
            state.failureKey = "garage.error.delete"
        }
    }
}
