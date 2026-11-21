import Foundation

/// 取り込みの流れが知らせる出来事です。
nonisolated enum RoadRegulationImportEvent: Equatable, Sendable {
    /// 段階または進み具合が変わった。
    case progress(RoadRegulationImportPhase)
    /// 取り込みが完了し、版を有効にした。
    case completed(RoadRegulationDataset)
}
