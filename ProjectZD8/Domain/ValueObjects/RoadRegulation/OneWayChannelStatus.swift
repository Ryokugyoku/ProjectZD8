import Foundation

/// 一方通行の経路でいま乗っている規制の状態です。
nonisolated enum OneWayChannelStatus: Equatable, Sendable {
    /// まだ確定していない。
    case pending
    /// 一方通行の区間に乗っていない。
    case none
    /// 一方通行の区間を指定の向きで進んでいる。
    case on(RoadRegulationID, OneWayTravelDirection)
    /// 判定できない(理由と、分かれば規制)。
    case undeterminable(RoadRegulationUndeterminedReason, RoadRegulationID?)
}
