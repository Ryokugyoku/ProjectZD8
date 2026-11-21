import Foundation

/// matcher が点から点へ持ち越す状態です。外からは読むだけで、更新は matcher が新しい値を作って行います。
nonisolated struct RoadRegulationMatchState: Equatable, Sendable {
    /// 走り始めの状態です(3つの経路は `pending`)。
    static let initial = RoadRegulationMatchState(
        heading: .initial,
        speedLimit: RoadRegulationStatusConfirmation(initial: .pending),
        oneWay: RoadRegulationStatusConfirmation(initial: .pending),
        slowDown: RoadRegulationStatusConfirmation(initial: .pending),
        stops: .initial,
        lastUsableMark: nil
    )

    /// 進む向きの推定。
    let heading: RoadRegulationHeadingState
    /// 最高速度の経路の確定待ち。
    let speedLimit: RoadRegulationStatusConfirmation<SpeedLimitStatus>
    /// 一方通行の経路の確定待ち。
    let oneWay: RoadRegulationStatusConfirmation<OneWayChannelStatus>
    /// 徐行の経路の確定待ち。
    let slowDown: RoadRegulationStatusConfirmation<SlowDownChannelStatus>
    /// 一時停止の追跡。
    let stops: StopApproachTrackerState
    /// 最後に使えた点の印。まだ無ければ `nil`。
    let lastUsableMark: RoadRegulationTransitionMark?
}
