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
    /// 現在の車両を所有するAppleアカウント識別子です。
    @ObservationIgnored private var accountIdentifier: String?

    /// 初期状態と注入済み境界を使ってモデルを生成します。
    ///
    /// 責務: 車両管理状態を永続化、OBD識別、画像取込の各境界へ結び付けます。
    /// - Parameters:
    ///   - state: 初期表示状態。
    ///   - repository: アカウントスコープ付き車両保存先。
    ///   - identifyForConnection: VINまたは非VIN識別子の取得と登録照合を行うユースケース。
    ///   - photoImporter: 選択画像をプロフィールデータへ変換する境界。
    init(
        state: VehicleManagementState,
        repository: any VehicleRepository,
        identifyForConnection: IdentifyVehicleForConnectionUseCase,
        photoImporter: any VehiclePhotoImportPort
    ) {
        self.state = state
        self.repository = repository
        self.identifyForConnection = identifyForConnection
        self.photoImporter = photoImporter
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
    /// 責務: 現在の1件のアカウントスコープへ車両一覧読込結果を反映します。
    private func loadVehicles() async {
        guard let accountIdentifier else { return }
        state.phase = .loading
        do {
            state.vehicles = try await repository.loadVehicles(for: accountIdentifier)
            state.hasLoadedVehicles = true
            state.phase = .idle
            state.failureKey = nil
        } catch {
            state.phase = .failed
            state.failureKey = "garage.error.sync"
        }
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
        do {
            switch try await identifyForConnection.execute(endpoint: endpoint, vehicles: state.vehicles) {
            case let .registered(vehicle):
                state.connectionVehicle = vehicle
                state.phase = .readyToConnect
            case let .requiresRegistration(snapshot):
                state.pendingIdentification = snapshot
                state.phase = .confirmingIdentification
            }
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
