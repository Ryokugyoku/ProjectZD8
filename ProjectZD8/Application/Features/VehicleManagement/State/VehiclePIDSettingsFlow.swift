/// 車両別の対応PID収集設定と車種専用PIDの登録状態を、PID保存先から車両管理状態へ反映します。
struct VehiclePIDSettingsFlow {
    /// 車両別対応PID設定の永続化境界です。
    let pidCapabilityRepository: (any VehiclePIDCapabilityRepository)?
    /// PID名称を解決するカタログ境界です。
    let pidDefinitionRepository: (any OBDPIDDefinitionRepository)?

    /// PID収集設定に関する1件の操作を現在状態へ反映します。
    ///
    /// 責務: PID設定の表示・選択変更・終了の各操作を、対応する読込・保存・解除1件へ振り分けます。
    /// それ以外の操作は状態を変えません。
    /// - Parameters:
    ///   - action: PlatformまたはAppから通知された操作。
    ///   - state: 更新する車両管理状態。
    func apply(_ action: VehicleManagementAction, to state: inout VehicleManagementState) {
        switch action {
        case let .pidSettingsRequested(vehicleID):
            loadSettings(for: vehicleID, into: &state)
        case let .pidCollectionChanged(request, isEnabled):
            updateSelection(request, isEnabled: isEnabled, in: &state)
        case .pidSettingsClosed:
            state.pidSettingsVehicleID = nil
            state.pidSelectionItems = []
        default:
            break
        }
    }

    /// 登録車両ごとの車種専用PID型式を求めます。
    ///
    /// 責務: 保存済みPID能力と定義から、車種専用PIDを登録済みの車両ごとの型式を返します。
    /// - Parameter vehicles: 対象の登録車両一覧。
    /// - Returns: 車両IDごとの型式。PID保存先か定義を利用できない場合は `nil`。
    func specialModelCodes(for vehicles: [VehicleProfile]) -> [VehicleID: String]? {
        guard let pidCapabilityRepository, let pidDefinitionRepository,
              let definitions = try? pidDefinitionRepository.definitions() else { return nil }
        let modelCodes = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
            definition.vehicleModelCode.map {
                (OBDPIDRequest(service: definition.service, pid: definition.pid), $0)
            }
        })
        var registrations: [VehicleID: String] = [:]
        for vehicle in vehicles where ZD8VehicleModelPolicy().matches(vehicle) {
            guard let capabilities = try? pidCapabilityRepository.capabilities(for: vehicle.id),
                  let modelCode = capabilities.lazy.compactMap({ modelCodes[$0.id.request] }).first else { continue }
            registrations[vehicle.id] = modelCode
        }
        return registrations
    }

    /// 指定車両の対応PIDと名称を収集設定状態へ読み込みます。
    ///
    /// 責務: 1件の車両IDをPIDテーブル名称付き収集選択一覧へ変換します。
    /// - Parameters:
    ///   - vehicleID: 設定対象のアプリ内車両ID。
    ///   - state: 更新する車両管理状態。
    private func loadSettings(for vehicleID: VehicleID, into state: inout VehicleManagementState) {
        guard let pidCapabilityRepository, let pidDefinitionRepository else {
            state.failureKey = "garage.pid_settings.error"
            return
        }
        do {
            let definitions = try pidDefinitionRepository.definitions()
            let names = Dictionary(uniqueKeysWithValues: definitions.map {
                (OBDPIDRequest(service: $0.service, pid: $0.pid), $0.nameKey)
            })
            let modelCodes = Dictionary(uniqueKeysWithValues: definitions.map {
                (OBDPIDRequest(service: $0.service, pid: $0.pid), $0.vehicleModelCode)
            })
            state.pidSelectionItems = try pidCapabilityRepository.capabilities(for: vehicleID).map {
                VehiclePIDSelectionItem(
                    id: $0.id.request,
                    nameKey: names[$0.id.request],
                    isEnabled: $0.isCollectionEnabled,
                    vehicleModelCode: modelCodes[$0.id.request] ?? nil
                )
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
    ///   - state: 更新する車両管理状態。
    private func updateSelection(_ request: OBDPIDRequest, isEnabled: Bool, in state: inout VehicleManagementState) {
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
}
