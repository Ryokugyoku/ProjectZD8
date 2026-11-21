import Foundation

/// 最高速度の経路でいま乗っている規制の状態です。
nonisolated enum SpeedLimitStatus: Equatable, Sendable {
    /// 開始直後・空白の後で、まだ確定していない。
    case pending
    /// 指定なし(法定速度とみなし、判定しない)。
    case unregulated
    /// 最高速度の規制に乗っている。
    case regulated(RoadRegulationID, limitKph: Int)
    /// 判定できない(理由と、分かれば規制)。
    case undeterminable(RoadRegulationUndeterminedReason, RoadRegulationID?)
}
