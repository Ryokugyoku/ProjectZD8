import Foundation

/// 有効にした交通規制データの版(1都道府県・1回の取り込み)です。
nonisolated struct RoadRegulationDataset: Equatable, Sendable {
    /// 版の識別子。
    let id: RoadRegulationDatasetID
    /// 都道府県。
    let prefecture: JapanesePrefectureCode
    /// 版の状態。
    let state: RoadRegulationDatasetState
    /// データの基準月。
    let dataMonth: RoadRegulationDataMonth
    /// 配布の公開時刻の印(12桁)。
    let publicationStamp: String
    /// ZIP の取得元 URL。
    let sourceURL: URL
    /// ZIP を受け取った時刻。
    let downloadedAt: Date
    /// 有効にした時刻。
    let activatedAt: Date
    /// CSV の版。
    let formatVersion: String
    /// 行の件数。
    let counts: RoadRegulationImportCounts
    /// 取り込んだ規制の形状をすべて含む範囲。
    let coverage: GeoBoundingBox
}
