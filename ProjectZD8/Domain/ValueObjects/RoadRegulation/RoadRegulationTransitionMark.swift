import Foundation

/// 状態が変わった軌跡の点の印です。
nonisolated struct RoadRegulationTransitionMark: Equatable, Sendable {
    /// 選んだ時刻軸の秒。
    let time: TimeInterval
    /// 位置サンプルの連番。
    let sequence: Int64
    /// 実時間。
    let observedAt: Date
}
