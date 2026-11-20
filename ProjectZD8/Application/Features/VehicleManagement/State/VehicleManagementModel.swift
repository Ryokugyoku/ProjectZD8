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
    /// 車両別対応PID収集設定と車種専用PID登録状態を状態へ反映する処理です。
    @ObservationIgnored private let pidSettings: VehiclePIDSettingsFlow
    /// 新規登録・編集の入力開始と終了を状態へ反映する処理です。
    @ObservationIgnored private let profileEditing = VehicleProfileEditingFlow()
    /// 接続履歴を車両別の軽量集計へ変換するユースケースです。
    @ObservationIgnored private let loadVehicleActivitySummaries: LoadVehicleActivitySummariesUseCase?
    /// 車両と関連セッションを全端末から削除するユースケースです。
    @ObservationIgnored private let deleteVehicleWithSessions: DeleteVehicleWithSessionsUseCase?
    /// 車両関連セッション削除後に履歴表示へ再読込を通知する処理です。
    @ObservationIgnored private let vehicleSessionsDidDelete: @MainActor () -> Void
    /// 接続対象車両、終端、編集前のOBD識別観測をLoggingと監視開始へ通知する処理です。
    @ObservationIgnored private let connectionVehicleDidResolve: @MainActor (
        VehicleProfile,
        OBDConnectionEndpoint,
        VehicleIdentificationSnapshot
    ) -> Void
    /// 新規登録した車両をアカウントと共に通知し、観測VINが一致する未割当セッションへ紐付ける処理です。
    @ObservationIgnored private let vehicleDidRegister: @MainActor (VehicleProfile, String) throws -> Void
    /// 接続のための車両識別がアダプターへ接続し始めることを通知する処理です。
    @ObservationIgnored private let connectionIdentificationWillBegin: @MainActor () -> Void
    /// 接続のための車両識別が終わったこと(成功・失敗・登録確認待ちのすべて)を通知する処理です。
    @ObservationIgnored private let connectionIdentificationDidEnd: @MainActor () -> Void
    /// 識別した車両が未登録のとき、車両なしで接続を始めるよう通知する処理です。
    @ObservationIgnored private let unregisteredConnectionDidStart: @MainActor (
        OBDConnectionEndpoint,
        VehicleIdentificationSnapshot
    ) -> Void
    /// 車両なしで始めた接続の途中で、その車両が登録されたことを通知する処理です。
    @ObservationIgnored private let unregisteredConnectionVehicleDidRegister: @MainActor (VehicleProfile) -> Void
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
    ///   - loadVehicleActivitySummaries: 接続履歴をGarage表示用集計へ変換するユースケース。
    ///   - deleteVehicleWithSessions: 車両と関連セッションを全端末から削除するユースケース。
    ///   - vehicleSessionsDidDelete: 車両関連セッション削除後に履歴表示へ再読込を通知する処理。
    ///   - connectionVehicleDidResolve: 接続対象車両、終端、編集前のOBD識別観測を通知する処理。
    ///   - unregisteredConnectionDidStart: 識別した車両が未登録のとき、車両なしの接続開始を通知する処理。
    ///   - unregisteredConnectionVehicleDidRegister: 車両なしで始めた接続の途中で登録された車両を通知する処理。
    ///   - vehicleDidRegister: 新規登録の保存成功後に車両とアカウント識別子を受け取る処理。throw すると保存は成功のまま
    ///     `garage.error.session_assignment` を表示します。
    ///   - connectionIdentificationWillBegin: 接続のための車両識別を始める直前に呼ぶ処理。
    ///   - connectionIdentificationDidEnd: 接続のための車両識別が終わった時に必ず1回呼ぶ処理(車両・未登録の通知の後)。
    init(
        state: VehicleManagementState,
        repository: any VehicleRepository,
        identifyForConnection: IdentifyVehicleForConnectionUseCase,
        photoImporter: any VehiclePhotoImportPort,
        pidCapabilityRepository: (any VehiclePIDCapabilityRepository)? = nil,
        pidDefinitionRepository: (any OBDPIDDefinitionRepository)? = nil,
        loadVehicleActivitySummaries: LoadVehicleActivitySummariesUseCase? = nil,
        deleteVehicleWithSessions: DeleteVehicleWithSessionsUseCase? = nil,
        vehicleSessionsDidDelete: @escaping @MainActor () -> Void = {},
        connectionVehicleDidResolve: @escaping @MainActor (
            VehicleProfile,
            OBDConnectionEndpoint,
            VehicleIdentificationSnapshot
        ) -> Void = { _, _, _ in },
        unregisteredConnectionDidStart: @escaping @MainActor (
            OBDConnectionEndpoint,
            VehicleIdentificationSnapshot
        ) -> Void = { _, _ in },
        unregisteredConnectionVehicleDidRegister: @escaping @MainActor (VehicleProfile) -> Void = { _ in },
        vehicleDidRegister: @escaping @MainActor (VehicleProfile, String) throws -> Void = { _, _ in },
        connectionIdentificationWillBegin: @escaping @MainActor () -> Void = {},
        connectionIdentificationDidEnd: @escaping @MainActor () -> Void = {}
    ) {
        self.state = state
        self.repository = repository
        self.identifyForConnection = identifyForConnection
        self.photoImporter = photoImporter
        self.pidSettings = VehiclePIDSettingsFlow(
            pidCapabilityRepository: pidCapabilityRepository,
            pidDefinitionRepository: pidDefinitionRepository
        )
        self.loadVehicleActivitySummaries = loadVehicleActivitySummaries
        self.deleteVehicleWithSessions = deleteVehicleWithSessions
        self.vehicleSessionsDidDelete = vehicleSessionsDidDelete
        self.connectionVehicleDidResolve = connectionVehicleDidResolve
        self.vehicleDidRegister = vehicleDidRegister
        self.connectionIdentificationWillBegin = connectionIdentificationWillBegin
        self.connectionIdentificationDidEnd = connectionIdentificationDidEnd
        self.unregisteredConnectionDidStart = unregisteredConnectionDidStart
        self.unregisteredConnectionVehicleDidRegister = unregisteredConnectionVehicleDidRegister
    }

    /// 1件の型付き操作を車両管理状態と副作用へ反映します。
    ///
    /// 責務: 車両管理操作を、識別・登録編集・PID設定・非同期の永続化ワークフローのいずれか1件へ振り分けます。
    /// - Parameter action: PlatformまたはAppから通知された操作。
    func send(_ action: VehicleManagementAction) {
        switch action {
        case let .accountIdentifierChanged(identifier): activateAccount(identifier)
        case let .identifyRequested(endpoint): Task { await identifyVehicle(using: endpoint) }
        case .identificationRetryRequested: retryIdentification()
        case .identificationConfirmed, .observedVINRegistrationRequested, .registrationCancelled,
             .editRequested, .editCancelled:
            profileEditing.apply(action, to: &state)
        case .pidSettingsRequested, .pidCollectionChanged, .pidSettingsClosed:
            pidSettings.apply(action, to: &state)
        case .vehicleSaved, .photoSelected, .vehicleDeleted, .refreshRequested:
            startPersistenceWorkflow(for: action)
        case let .connectionSessionActivityChanged(isSessionActive):
            applyConnectionSessionActivity(isSessionActive: isSessionActive)
        }
    }

    /// 接続セッションの開始・続行・終了を、車両別の活動の集計と接続待ちの段階へ反映します。
    ///
    /// 責務: 活動の集計を読み直し、セッションが無くなった時だけ接続待ち(`.readyToConnect`)を操作待ちへ戻します。
    /// セッションがある時と、接続待ち以外の段階は変えません(識別の途中で届いても順序に依存させないため)。
    /// アカウントが無い時は何もしません。
    /// - Parameter isSessionActive: 通知の時点で現在の接続セッションがあるかどうか。
    private func applyConnectionSessionActivity(isSessionActive: Bool) {
        guard let accountIdentifier else { return }
        loadActivitySummaries(for: accountIdentifier)
        guard !isSessionActive, state.phase == .readyToConnect else { return }
        state.phase = .idle
    }

    /// 直前と同じOBD終端で車両識別を再試行します。
    ///
    /// 責務: 保持中の接続終端がある時だけ、その終端で識別ワークフロー1件を開始します。
    private func retryIdentification() {
        guard let endpoint = state.connectionEndpoint else { return }
        Task { await identifyVehicle(using: endpoint) }
    }

    /// 保存・写真取込・削除・再読込の操作を非同期ワークフローとして開始します。
    ///
    /// 責務: 永続化や取込を伴う操作1件を、対応する非同期ワークフロー1件へ振り分けます。それ以外の操作は無視します。
    /// - Parameter action: PlatformまたはAppから通知された操作。
    private func startPersistenceWorkflow(for action: VehicleManagementAction) {
        switch action {
        case let .vehicleSaved(vehicle): Task { await save(vehicle) }
        case let .photoSelected(url): Task { await importPhoto(at: url) }
        case let .vehicleDeleted(id): Task { await delete(id) }
        case .refreshRequested: Task { await refresh() }
        default: break
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
            let syncResult = VehicleCatalogReconciliation(local: state.vehicles, remote: remote)
            state.vehicles = syncResult.merged
            state.hasLoadedVehicles = true
            loadActivitySummaries(for: accountIdentifier)
            if let registrations = pidSettings.specialModelCodes(for: state.vehicles) {
                state.specialPIDModelCodeByVehicleID = registrations
            }
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

    /// 現在アカウントの接続履歴をGarage用の車両別集計へ読み込みます。
    ///
    /// 責務: 1件のアカウント識別子へ対応する車両別ログ集計を現在状態へ反映します。
    /// - Parameter accountIdentifier: 集計対象のAppleアカウント識別子。
    private func loadActivitySummaries(for accountIdentifier: String) {
        guard let loadVehicleActivitySummaries else { return }
        state.activityByVehicleID = (try? loadVehicleActivitySummaries.execute(
            accountIdentifier: accountIdentifier
        )) ?? [:]
    }

    /// 要求された再読込として、活動の集計を読み直し、操作待ちの時だけ車両一覧も読み直します。
    ///
    /// 責務: 段階に関わらず車両別の活動の集計を読み直し、進行中の識別・登録・編集・接続待ちの状態を保持したまま、
    /// 操作待ち時だけ車両カタログ再読込を開始します。
    private func refresh() async {
        guard let accountIdentifier else { return }
        loadActivitySummaries(for: accountIdentifier)
        guard state.phase == .idle else { return }
        await loadVehicles()
    }

    /// OBD識別結果を登録済み接続または登録確認へ反映します。
    ///
    /// 責務: 1回のHOME接続要求を車両識別子の照合結果に応じた状態へ進めます。
    /// 未登録なら登録確認へ進めると同時に、車両なしの接続開始を通知します。
    /// - Parameter endpoint: 接続するOBDアダプターの物理終端。
    private func identifyVehicle(using endpoint: OBDConnectionEndpoint) async {
        guard accountIdentifier != nil, state.phase != .identifying else { return }
        connectionIdentificationWillBegin()
        defer { connectionIdentificationDidEnd() }
        state.connectionEndpoint = endpoint
        state.phase = .identifying
        state.failureKey = nil
        state.identificationFailureStage = nil
        do {
            let result = try await identifyForConnection.execute(endpoint: endpoint, vehicles: state.vehicles)
            applyIdentificationResult(result, endpoint: endpoint)
        } catch {
            let failure = VehicleIdentificationFailure(error: error)
            state.phase = .failed
            state.identificationFailureStage = failure.stage
            state.failureKey = failure.failureKey
        }
    }

    /// 成功した車両識別の照合結果を接続待ちまたは登録確認へ反映します。
    ///
    /// 責務: 1件の照合結果を、登録済みなら接続対象の確定と通知へ、未登録なら登録確認と車両なし接続の通知へ変換します。
    /// - Parameters:
    ///   - result: 識別ユースケースが返した照合結果。
    ///   - endpoint: 識別に使ったOBDアダプターの物理終端。
    private func applyIdentificationResult(
        _ result: IdentifyVehicleForConnectionUseCase.Outcome,
        endpoint: OBDConnectionEndpoint
    ) {
        switch result {
        case let .registered(vehicle, snapshot):
            state.connectionVehicle = vehicle
            state.phase = .readyToConnect
            connectionVehicleDidResolve(vehicle, endpoint, snapshot)
            if let accountIdentifier { loadActivitySummaries(for: accountIdentifier) }
        case let .requiresRegistration(snapshot):
            state.pendingIdentification = snapshot
            state.phase = .confirmingIdentification
            unregisteredConnectionDidStart(endpoint, snapshot)
        }
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
    /// 責務: 編集済み車両1件を保存し最新一覧へ置き換えます。接続時の識別から登録した場合は、
    /// 車両なしで始めた接続へ登録した車両を通知します(新しい接続は始めません)。
    /// - Parameter vehicle: 保存する編集済みプロフィール。
    private func save(_ vehicle: VehicleProfile) async {
        guard let accountIdentifier else { return }
        let isRegistration = state.phase == .registering
        let connectionIdentification = isRegistration ? state.pendingIdentification : nil
        var saved = vehicle
        saved.updatedAt = Date()
        do {
            try await repository.saveVehicle(saved, for: accountIdentifier)
            // 新規登録の通知先が throw しても保存は成功のまま扱い、紐付け失敗の文言だけを出す。
            let didNotifyRegistration = !isRegistration || (try? vehicleDidRegister(saved, accountIdentifier)) != nil
            if let index = state.vehicles.firstIndex(where: { $0.id == saved.id }) {
                state.vehicles[index] = saved
            } else {
                state.vehicles.append(saved)
            }
            state.vehicles.sort { $0.updatedAt > $1.updatedAt }
            state.editingVehicle = nil
            state.pendingIdentification = nil
            if connectionIdentification != nil {
                state.connectionVehicle = saved
                unregisteredConnectionVehicleDidRegister(saved)
            }
            loadActivitySummaries(for: accountIdentifier)
            state.phase = .idle
            state.failureKey = didNotifyRegistration ? nil : "garage.error.session_assignment"
        } catch {
            state.vehicles = (try? await repository.loadVehicles(for: accountIdentifier)) ?? state.vehicles
            state.phase = .failed
            state.failureKey = "garage.error.save"
        }
    }

    /// 指定車両と関連セッションを現在アカウントから削除します。
    ///
    /// 責務: 指定IDの車両1件と全関連セッションを削除して表示一覧へ成功結果を反映します。
    /// - Parameter id: 削除対象のアプリ内車両ID。
    private func delete(_ id: VehicleID) async {
        guard let accountIdentifier else { return }
        guard let deleteVehicleWithSessions else {
            state.phase = .failed
            state.failureKey = "garage.error.delete"
            return
        }
        do {
            try await deleteVehicleWithSessions.execute(
                vehicleID: id,
                accountIdentifier: accountIdentifier
            )
            state.vehicles.removeAll { $0.id == id }
            state.activityByVehicleID[id] = nil
            state.editingVehicle = nil
            state.phase = .idle
            state.failureKey = nil
            vehicleSessionsDidDelete()
        } catch DeleteVehicleWithSessionsUseCase.Error.activeSession {
            state.phase = .failed
            state.failureKey = "garage.error.delete_active_session"
        } catch {
            state.phase = .failed
            state.failureKey = "garage.error.delete"
        }
    }
}
