import Foundation

/// 最高速度の区間の判定です(文言を持ちません)。
nonisolated enum SpeedLimitVerdict: Equatable, Sendable {
    /// 制限内だった(区間内の最高車速)。
    case withinLimit(maxKph: Double)
    /// 超過した(超過の連続の最高車速と、連続の秒数の合計)。
    case exceeded(maxKph: Double, exceededSeconds: Double)
    /// 指定なし(判定しない)。
    case unregulated
    /// 判定できない。
    case undeterminable(RoadRegulationUndeterminedReason)
}
