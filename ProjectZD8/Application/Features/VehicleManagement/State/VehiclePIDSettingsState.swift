/// 開いているPID収集設定画面の状態です。
nonisolated struct VehiclePIDSettingsState: Equatable, Sendable {
    /// 対象の車両IDです。
    let vehicleID: VehicleID
    /// 対象の車両名です。
    let vehicleName: String
    /// 変換できる定義すべての項目です。
    var items: [VehiclePIDSettingItem]
    var categoryFilter: VehiclePIDCategoryFilter = .all
    var enabledFilter: VehiclePIDEnabledFilter = .all

    /// 絞り込み後に表示する項目です。
    var visibleItems: [VehiclePIDSettingItem] {
        items.filter { categoryFilter.matches($0) && enabledFilter.matches($0) }
    }
    /// 収集が有効な項目数です。
    var enabledCount: Int { items.filter(\.isEnabled).count }
    /// 車両が応答すると確認できた項目数です。
    var supportedCount: Int { items.filter(\.isSupported).count }
    /// 一覧に現れる標準PIDの分類です。
    var availableCategories: [OBDPIDCategory] {
        OBDPIDCategory.allCases.filter { category in items.contains { $0.category == category } }
    }
    /// 車種専用PIDを含むかどうかです。
    var hasVehicleSpecificItems: Bool { items.contains(where: \.isVehicleSpecific) }
}
