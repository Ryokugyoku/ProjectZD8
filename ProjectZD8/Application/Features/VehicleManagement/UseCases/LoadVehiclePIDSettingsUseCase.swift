import Foundation

/// 車両のPID定義と保存済みの収集設定を結び付けます。
nonisolated struct LoadVehiclePIDSettingsUseCase: Sendable {
    private let settings: any VehiclePIDSettingRepository

    /// 責務: PID設定の取得先を固定します。
    init(settings: any VehiclePIDSettingRepository) {
        self.settings = settings
    }

    /// 車両のPID収集設定の一覧を作ります。
    ///
    /// 責務: 車種コードに対応する変換可能な定義へ、保存済みの対応状況と収集設定を結合します。応答を確認できていないPIDは収集されないため、有効としては扱いません。
    /// - Parameter vehicle: 対象の車両。
    /// - Returns: 標準PID、続いて車種専用PIDの順に並べた項目。
    /// - Throws: 設定を読み込めない場合の永続化エラー。
    func execute(for vehicle: Vehicle) async throws -> [VehiclePIDSettingItem] {
        let stored = Dictionary(
            try await settings.settings(for: vehicle.id).map { ($0.request, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        return OBDPIDCatalog.definitions(forVehicleModelCode: vehicle.modelCode)
            .filter(\.isDecodable)
            .map { definition in
                let setting = stored[definition.request]
                return VehiclePIDSettingItem(
                    request: definition.request,
                    nameKey: definition.nameKey,
                    unit: definition.unit,
                    category: definition.isVehicleSpecific ? nil : OBDPIDCategory.category(for: definition.request),
                    isVehicleSpecific: definition.isVehicleSpecific,
                    support: setting.map { $0.isSupported ? .supported : .unsupported } ?? .unknown,
                    isEnabled: (setting?.isSupported ?? false) && (setting?.isCollectionEnabled ?? false)
                )
            }
    }
}
