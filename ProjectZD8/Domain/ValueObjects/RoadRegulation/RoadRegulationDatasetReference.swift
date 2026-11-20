import Foundation

/// 判定に使った規制データの版の参照です。
nonisolated struct RoadRegulationDatasetReference: Equatable, Sendable {
    /// 都道府県。
    let prefecture: JapanesePrefectureCode
    /// データの基準月。
    let dataMonth: RoadRegulationDataMonth
}
