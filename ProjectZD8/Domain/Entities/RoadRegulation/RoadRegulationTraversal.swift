import Foundation

/// 1つの経路で同じ状態が続いた区間の通過です。
nonisolated struct RoadRegulationTraversal: Equatable, Sendable {
    /// 区間の状態。
    let status: RoadRegulationTraversalStatus
    /// 区間の最初の点。
    let start: RoadRegulationTransitionMark
    /// 区間の最後の点。
    let end: RoadRegulationTransitionMark
    /// 区間が終わった理由。
    let endReason: RoadRegulationTraversalEndReason
}
