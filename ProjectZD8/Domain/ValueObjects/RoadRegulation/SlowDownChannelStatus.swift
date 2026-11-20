import Foundation

/// 徐行の経路でいま乗っている規制の状態です。
nonisolated enum SlowDownChannelStatus: Equatable, Sendable {
    /// まだ確定していない。
    case pending
    /// 徐行の区間に乗っていない。
    case none
    /// 徐行の区間に乗っている。
    case on(RoadRegulationID)
    /// 判定できない(理由と、分かれば規制)。
    case undeterminable(RoadRegulationUndeterminedReason, RoadRegulationID?)
}
