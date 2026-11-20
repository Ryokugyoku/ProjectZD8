import Foundation

/// 保存前の交通規制と、その形状が覆う升目の組です。
nonisolated struct RoadRegulationIndexedDraft: Equatable, Sendable {
    /// 保存する規制。
    let draft: RoadRegulationDraft
    /// 形状が覆う升目(昇順・重複なし)。
    let cells: [RoadRegulationCellKey]
}
