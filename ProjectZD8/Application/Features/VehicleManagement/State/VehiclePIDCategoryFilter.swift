/// PID収集設定を分類で絞り込む条件です。
nonisolated enum VehiclePIDCategoryFilter: Hashable, Sendable {
    /// すべての分類を表示します。
    case all
    /// 標準PIDの1分類だけを表示します。
    case category(OBDPIDCategory)
    /// 車種専用PIDだけを表示します。
    case vehicleSpecific

    /// 項目が条件に合うかを返します。
    ///
    /// 責務: 1項目を分類条件で判定します。
    func matches(_ item: VehiclePIDSettingItem) -> Bool {
        switch self {
        case .all: true
        case let .category(category): item.category == category
        case .vehicleSpecific: item.isVehicleSpecific
        }
    }
}

/// PID収集設定を有効状態で絞り込む条件です。
nonisolated enum VehiclePIDEnabledFilter: String, CaseIterable, Sendable {
    case all
    case enabled
    case disabled

    /// 表示名のローカライズキーです。
    var nameKey: String { "garage.pid_settings.filter.\(rawValue)" }

    /// 項目が条件に合うかを返します。
    ///
    /// 責務: 1項目を有効状態で判定します。
    func matches(_ item: VehiclePIDSettingItem) -> Bool {
        switch self {
        case .all: true
        case .enabled: item.isEnabled
        case .disabled: !item.isEnabled
        }
    }
}
