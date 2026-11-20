import Foundation

/// 最高速度の区間1つの判定結果です。
nonisolated struct SpeedLimitJudgement: Equatable, Sendable {
    /// 判定した区間。
    let traversal: RoadRegulationTraversal
    /// 制限速度(km/h)。規制に乗っていなければ `nil`。
    let limitKph: Int?
    /// 判定。
    let verdict: SpeedLimitVerdict
}
