/// 長期傾向に現れるチャンネルのメタデータです。
nonisolated struct VehicleTrendChannel: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let unit: String
}
