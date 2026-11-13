/// 分析対象セッションの車両属性です。
nonisolated struct AnalysisVehicleInfo: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let manufacturer: String
    let engineModel: String
    let modelYear: Int?
    let powertrain: String
}
