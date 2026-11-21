import Foundation

/// 一方通行の区間1つの判定結果です。
nonisolated struct OneWayJudgement: Equatable, Sendable {
    /// 判定した区間。
    let traversal: RoadRegulationTraversal
    /// 判定。
    let verdict: OneWayVerdict
}
