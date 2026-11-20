import Foundation

/// 一時停止の通過の判定です(文言を持ちません)。
nonisolated enum StopVerdict: Equatable, Sendable {
    /// 停止した。
    case stopped
    /// 停止しなかった(接近中の最低車速)。
    case notStopped(minimumKph: Double)
    /// 判定できない。
    case undeterminable(RoadRegulationUndeterminedReason)
}
