import Foundation

/// 取り込みを終えた版を有効にする時に記録する結果です。
nonisolated struct RoadRegulationImportSummary: Equatable, Sendable {
    /// データの基準月。
    let dataMonth: RoadRegulationDataMonth
    /// CSV の版(例 "k_2.1")。
    let formatVersion: String
    /// 行の件数。
    let counts: RoadRegulationImportCounts
    /// 取り込んだ規制の形状をすべて含む範囲。
    let coverage: GeoBoundingBox
}
