import Foundation

/// matcher の1歩で起きた変化です。
nonisolated enum RoadRegulationChange: Equatable, Sendable {
    /// 最高速度の経路の状態が切り替わった。
    case speedLimitChanged(from: SpeedLimitStatus, to: SpeedLimitStatus, since: RoadRegulationTransitionMark)
    /// 一方通行の経路の状態が切り替わった。
    case oneWayChanged(from: OneWayChannelStatus, to: OneWayChannelStatus, since: RoadRegulationTransitionMark)
    /// 徐行の経路の状態が切り替わった。
    case slowDownChanged(from: SlowDownChannelStatus, to: SlowDownChannelStatus, since: RoadRegulationTransitionMark)
    /// 一時停止への接近が始まった。
    case stopApproachStarted(StopApproachKey, RoadRegulationTransitionMark)
    /// 一時停止の停止点へ到達した。
    case stopReached(StopPassage)
    /// 一時停止への接近を打ち切った(判定に数えない)。
    case stopApproachAbandoned(StopApproachKey)
    /// 位置の記録が途切れた。
    case trackGap(lastUsable: RoadRegulationTransitionMark)
}
