/// 整備を記録する車両の選択肢です。
nonisolated struct MaintenanceVehicleOption: Identifiable, Equatable, Sendable {
    /// 車両IDです。
    let id: VehicleID
    /// 車両名です。
    let name: String
}
