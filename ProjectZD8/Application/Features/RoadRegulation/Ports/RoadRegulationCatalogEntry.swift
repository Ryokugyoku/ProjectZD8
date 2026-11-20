import Foundation

/// 配布の一覧にある1都道府県の ZIP です。
nonisolated struct RoadRegulationCatalogEntry: Equatable, Sendable {
    /// 都道府県。
    let prefecture: JapanesePrefectureCode
    /// ZIP の URL。
    let archiveURL: URL
    /// 配布の公開時刻の印(12桁。例 "202611010000")。
    let publicationStamp: String
}
