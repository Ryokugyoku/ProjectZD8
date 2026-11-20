import Foundation

/// いま乗っている規制(確定済みの状態)です。
nonisolated struct RoadRegulationPosition: Equatable, Sendable {
    /// 最高速度の経路。
    let speedLimit: SpeedLimitStatus
    /// 一方通行の経路。
    let oneWay: OneWayChannelStatus
    /// 徐行の経路。
    let slowDown: SlowDownChannelStatus
    /// 進行中の一時停止への接近。
    let activeStopApproaches: [StopApproachKey]
}
