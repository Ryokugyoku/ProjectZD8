/// 1台の車両について、セッションごとの集計を時間順に並べた長期傾向データです。
nonisolated struct VehicleTrendDataset: Codable, Equatable, Sendable {
    /// データセット形式の現行版です。
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let vehicle: AnalysisVehicleInfo
    let channels: [VehicleTrendChannel]
    /// 開始日時の昇順です。
    let sessions: [VehicleTrendSession]
    let maintenance: [AnalysisMaintenanceMarker]
    /// Rawが iCloud にだけあり集計できなかったセッション数です。
    let skippedCloudOnlySessions: Int
    /// 集計から除外したデモセッション数です。
    let excludedDemoSessions: Int
}
