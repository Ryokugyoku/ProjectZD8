import Foundation

/// 徐行の区間の判定です(文言を持ちません)。
nonisolated enum SlowDownVerdict: Equatable, Sendable {
    /// 区間内の最高車速と参考の速さ。
    case observed(maxKph: Double, referenceKph: Double)
    /// 判定できない。
    case undeterminable(RoadRegulationUndeterminedReason)
}
