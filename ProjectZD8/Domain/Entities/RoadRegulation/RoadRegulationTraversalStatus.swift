import Foundation

/// 区間の通過で乗っていた経路の状態です。
nonisolated enum RoadRegulationTraversalStatus: Equatable, Sendable {
    /// 最高速度の経路。
    case speedLimit(SpeedLimitStatus)
    /// 一方通行の経路。
    case oneWay(OneWayChannelStatus)
    /// 徐行の経路。
    case slowDown(SlowDownChannelStatus)
}
