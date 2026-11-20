import Foundation

/// 徐行の区間1つの判定結果です。
nonisolated struct SlowDownJudgement: Equatable, Sendable {
    /// 判定した区間。
    let traversal: RoadRegulationTraversal
    /// 判定。
    let verdict: SlowDownVerdict
}
