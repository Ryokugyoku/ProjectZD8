import Foundation

/// 軌跡の1点に対する線の規制の当てはまり具合です。
nonisolated struct RoadRegulationLineMatch: Equatable, Sendable {
    /// 候補の規制。
    let regulation: RoadRegulation
    /// 線までの距離(m)。
    let distanceMeters: Double
    /// 進む向きと線の向きの角度差(度)。向きが分からなければ `nil`。
    let headingDifference: Double?
    /// 一方通行の時の進む向き。向きを区別しない時と分からない時は `nil`。
    let travelDirection: OneWayTravelDirection?
    /// 点数(小さいほど良い)。
    let score: Double
    /// 最寄りの線分が粗いか。
    let isCoarse: Bool
    /// 除外の形状が許容内にあるか。
    let isNearExclusion: Bool
}
