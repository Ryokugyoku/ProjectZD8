import Foundation

/// 1件の観測(位置または PID の値)の時刻の組です。実時間と、あれば単調時刻を持ちます。
nonisolated struct TelemetryClockStamp: Equatable, Sendable {
    /// 観測した実時間です。
    let observedAt: Date
    /// 観測した単調時刻(ナノ秒)です。記録していない古いデータでは `nil` です。
    let monotonicNanoseconds: UInt64?
}
