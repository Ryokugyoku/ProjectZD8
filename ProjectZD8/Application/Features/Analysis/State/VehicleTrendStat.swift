/// 1セッション・1チャンネル・1条件の分布要約です。
nonisolated struct VehicleTrendStat: Codable, Equatable, Sendable {
    let channelId: String
    let condition: VehicleTrendCondition
    /// 条件を満たしたサンプル数です。
    let count: Int
    let median: Double
    let p05: Double
    let p95: Double
}
