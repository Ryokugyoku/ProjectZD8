import Foundation

/// 位置と車速を並べる時刻の軸です。
nonisolated enum RoadRegulationTimeAxis: String, Sendable {
    /// 単調時計(同じ起動中の記録)。
    case monotonic
    /// 実時間(`observedAt`)。
    case wallClock
}
