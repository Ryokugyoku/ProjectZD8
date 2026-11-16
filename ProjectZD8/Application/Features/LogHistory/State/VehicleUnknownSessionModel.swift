import Observation

/// 車両を特定できなかったログ(車両なし・観測VINなし)の警告と、登録済みの車両への紐付けを保持するモデルです。
///
/// 照会と紐付けはユースケースに任せ、このモデルは操作を状態へ反映するだけです。照会・紐付けの失敗は空や成功に潰さず、
/// 警告の `.loadFailed` と紐付け画面の `failureKey` で示します。
@MainActor
@Observable
final class VehicleUnknownSessionModel {
    /// ホームと車両画面に表示する警告です。
    private(set) var warning: VehicleUnknownSessionWarning = .hidden

    /// 紐付け画面の状態です。
    private(set) var assignment = VehicleUnknownSessionAssignmentState()

    /// 車両不明ログの照会です。
    @ObservationIgnored private let loadSessions: LoadVehicleUnknownConnectionSessionsUseCase

    /// 車両不明ログの紐付けです。
    @ObservationIgnored private let assignVehicle: AssignVehicleToVehicleUnknownConnectionSessionsUseCase

    /// サインイン中のアカウントの識別子です。
    @ObservationIgnored private var accountIdentifier: String?

    /// 照会と紐付けのユースケースを注入して生成します。
    ///
    /// 責務: 警告と紐付け画面の操作先を結び付けます。
    /// - Parameters:
    ///   - loadSessions: 車両不明ログの照会。
    ///   - assignVehicle: 車両不明ログの紐付け。
    init(
        loadSessions: LoadVehicleUnknownConnectionSessionsUseCase,
        assignVehicle: AssignVehicleToVehicleUnknownConnectionSessionsUseCase
    ) {
        self.loadSessions = loadSessions
        self.assignVehicle = assignVehicle
    }

    /// 1件の操作を反映します。
    ///
    /// 責務: 操作をアカウントの切替・再読込・画面の開閉・選択・紐付けへ振り分けます。
    /// - Parameter action: 画面またはAppから届いた操作。
    func send(_ action: VehicleUnknownSessionAction) {
        switch action {
        case let .accountIdentifierChanged(identifier):
            accountIdentifier = identifier
            assignment = VehicleUnknownSessionAssignmentState()
            reload()
        case .refreshRequested:
            reload()
        case .warningActionSelected(.reviewSessions):
            assignment.isPresented = true
            assignment.failureKey = nil
        case .warningActionSelected(.retryLoading):
            reload()
        case .assignmentDismissed:
            assignment = VehicleUnknownSessionAssignmentState(sessions: assignment.sessions)
        case let .sessionSelectionToggled(id):
            toggleSelection(id)
        case let .vehicleSelected(id):
            assignment.selectedVehicleID = id
            assignment.failureKey = nil
        case let .assignRequested(vehicles):
            assign(among: vehicles)
        }
    }

    /// 車両不明ログを読み込み直し、警告と紐付け画面の候補へ反映します。
    ///
    /// 責務: アカウントが未確定なら非表示にし、照会の失敗は `.loadFailed` にします。候補から消えたログの選択は外します。
    private func reload() {
        guard let accountIdentifier else {
            warning = .hidden
            assignment = VehicleUnknownSessionAssignmentState()
            return
        }
        do {
            let sessions = try loadSessions.execute(accountIdentifier: accountIdentifier)
            warning = VehicleUnknownSessionWarning(count: sessions.count)
            assignment.sessions = sessions
            assignment.selectedSessionIDs.formIntersection(sessions.map(\.id))
            if sessions.isEmpty { assignment.isPresented = false }
        } catch {
            warning = .loadFailed
        }
    }

    /// ログの選択を切り替えます。
    ///
    /// 責務: 候補にあるログだけを選択集合へ出し入れし、失敗の表示を消します。
    /// - Parameter id: 切り替えるログのID。
    private func toggleSelection(_ id: ConnectionSessionID) {
        guard assignment.sessions.contains(where: { $0.id == id }) else { return }
        if assignment.selectedSessionIDs.contains(id) {
            assignment.selectedSessionIDs.remove(id)
        } else {
            assignment.selectedSessionIDs.insert(id)
        }
        assignment.failureKey = nil
    }

    /// 選んだログを選んだ車両へ紐付けます。
    ///
    /// 責務: 実行できる選択の時だけ紐付けを依頼し、成功したら選択を消して読み込み直し、失敗したら文言キーを示します。
    /// - Parameter vehicles: 候補の登録済み車両。
    private func assign(among vehicles: [VehicleProfile]) {
        guard let accountIdentifier,
              assignment.canAssign(among: vehicles),
              let vehicle = vehicles.first(where: { $0.id == assignment.selectedVehicleID }) else { return }
        do {
            _ = try assignVehicle.execute(
                vehicle: vehicle,
                sessionIDs: Array(assignment.selectedSessionIDs),
                accountIdentifier: accountIdentifier
            )
            assignment.selectedSessionIDs = []
            assignment.failureKey = nil
            reload()
        } catch {
            assignment.failureKey = "vehicle_unknown.assignment.failure"
        }
    }
}
