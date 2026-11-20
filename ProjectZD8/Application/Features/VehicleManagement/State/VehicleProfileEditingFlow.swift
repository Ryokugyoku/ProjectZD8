/// 車両プロフィールの新規登録・編集の入力開始と終了を車両管理状態へ反映します。
struct VehicleProfileEditingFlow {
    /// 登録・編集の入力に関する1件の操作を現在状態へ反映します。
    ///
    /// 責務: 登録確認・観測VIN登録・登録取消・編集開始・編集終了の各操作を、対応する状態遷移1件へ振り分けます。
    /// それ以外の操作は状態を変えません。
    /// - Parameters:
    ///   - action: PlatformまたはAppから通知された操作。
    ///   - state: 更新する車両管理状態。
    func apply(_ action: VehicleManagementAction, to state: inout VehicleManagementState) {
        switch action {
        case .identificationConfirmed:
            beginRegistration(in: &state)
        case let .observedVINRegistrationRequested(vin):
            beginObservedVINRegistration(vin, in: &state)
        case .registrationCancelled:
            state.pendingIdentification = nil
            state.editingVehicle = nil
            state.phase = .idle
        case let .editRequested(id):
            beginEditing(id, in: &state)
        case .editCancelled:
            state.editingVehicle = nil
            state.phase = .idle
        default:
            break
        }
    }

    /// 確認済みOBD識別子から新規プロフィール入力を開始します。
    ///
    /// 責務: 保持中のVINまたは非VIN識別観測1件を編集可能な新規プロフィールへ変換します。
    /// - Parameter state: 更新する車両管理状態。
    private func beginRegistration(in state: inout VehicleManagementState) {
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
            isDefault: false
        )
        state.phase = .registering
    }

    /// 未登録ログで観測したVINから新規プロフィール入力を開始します。
    ///
    /// 責務: 1件の観測VINを、OBD識別観測を持たない編集可能な新規プロフィールへ変換します。
    /// - Parameters:
    ///   - vin: 未登録ログで観測したVIN。空白だけの場合は何もしません。
    ///   - state: 更新する車両管理状態。
    private func beginObservedVINRegistration(_ vin: String, in state: inout VehicleManagementState) {
        guard let normalized = ConnectionSession.normalizedObservedVIN(vin),
              [.idle, .readyToConnect, .failed].contains(state.phase) else { return }
        state.pendingIdentification = nil
        state.editingVehicle = VehicleProfile(
            vin: normalized,
            obdIdentifier: nil,
            name: "",
            manufacturer: "",
            engineModel: "",
            isDefault: false
        )
        state.failureKey = nil
        state.phase = .registering
    }

    /// 指定車両のプロフィール編集を開始します。
    ///
    /// 責務: 登録一覧から指定IDの車両1件を編集状態へ設定します。
    /// - Parameters:
    ///   - id: 編集対象のアプリ内車両ID。
    ///   - state: 更新する車両管理状態。
    private func beginEditing(_ id: VehicleID, in state: inout VehicleManagementState) {
        guard let vehicle = state.vehicles.first(where: { $0.id == id }) else { return }
        state.editingVehicle = vehicle
        state.phase = .editing
    }
}
