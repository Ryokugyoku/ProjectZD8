/// セッション選択の車両候補です。
nonisolated struct AnalysisVehicleOption: Identifiable, Equatable, Sendable {
    let id: VehicleID
    let name: String
}
