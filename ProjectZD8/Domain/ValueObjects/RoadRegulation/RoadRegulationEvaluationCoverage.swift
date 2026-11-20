import Foundation

/// 判定に使った入力の範囲と質です。
nonisolated struct RoadRegulationEvaluationCoverage: Equatable, Sendable {
    /// 選んだ時刻の軸。
    let timeAxis: RoadRegulationTimeAxis
    /// 使った軌跡の点数。
    let trackPointCount: Int
    /// 精度などで捨てた点数。
    let droppedPointCount: Int
    /// 車速の記録があったか。
    let hasVehicleSpeed: Bool
    /// 使った規制データの版。
    let datasets: [RoadRegulationDatasetReference]
}
