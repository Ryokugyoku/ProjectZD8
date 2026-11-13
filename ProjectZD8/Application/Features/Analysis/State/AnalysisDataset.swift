/// 1セッション分の、Webワークベンチへ渡す版管理付きデータセットです。
///
/// 値は取得時に固定したセッションPIDの規則で変換したものだけを含み、欠測は補間しません。
nonisolated struct AnalysisDataset: Codable, Equatable, Sendable {
    /// データセット形式の現行版です。
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let session: AnalysisSessionInfo
    let vehicle: AnalysisVehicleInfo
    let channels: [AnalysisChannel]
    let gaps: [AnalysisGap]
    /// 車両の整備記録です。新しい順ではなく日付の昇順に並べます。
    let maintenance: [AnalysisMaintenanceMarker]
}
