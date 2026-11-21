import Foundation

/// 位置と車速を並べる時刻の軸(単調時計か実時間か)を選びます。
///
/// 単調時計を使うのは、車速が空の時(位置には単調時刻が必ずある)と、車速のすべてに単調時刻があり、
/// 位置と車速の全サンプルで「実時間 − 単調時刻」のばらつき(最大 − 最小)が 2.0 秒以下の時(同じ起動中とみなせる)です。
nonisolated struct RoadRegulationTimeAxisPolicy: Sendable {
    /// 同じ起動中とみなす「実時間 − 単調時刻」のばらつきの上限(秒、この値を含む)。
    static let maximumClockOffsetSpreadSeconds = 2.0
    /// 実時間の丸め誤差を吸収する余裕(秒)。`Date` の倍精度の丸めで、ちょうど上限の値が上限を超えて見えるのを防ぎます。
    static let roundingToleranceSeconds = 1e-6
    /// 1秒のナノ秒数。
    private static let nanosecondsPerSecond = 1_000_000_000.0

    /// 選び方の規則を作ります。
    ///
    /// 責務: 状態を持たない規則を用意します。
    init() {}

    /// 時刻の軸を選びます。
    ///
    /// 責務: 車速の有無と単調時刻の有無を確かめ、2つの時計のずれのばらつきが上限以下なら単調時計を選びます。
    /// - Parameters:
    ///   - locations: 位置サンプル。
    ///   - speedEntries: Raw ログから取り出した車速。
    /// - Returns: 選んだ時刻の軸。
    func select(locations: [ConnectionSessionLocationSample], speedEntries: [VehicleSpeedRawObservation]) -> RoadRegulationTimeAxis {
        guard !speedEntries.isEmpty else { return .monotonic }
        let speedClocks = speedEntries.compactMap { entry in
            entry.monotonicNanoseconds.map { ClockReading(observedAt: entry.observedAt, monotonicNanoseconds: $0) }
        }
        guard speedClocks.count == speedEntries.count else { return .wallClock }
        let locationClocks = locations.map {
            ClockReading(observedAt: $0.fix.observedAt, monotonicNanoseconds: $0.fix.monotonicNanoseconds)
        }
        let spread = Self.offsetSpreadSeconds(of: locationClocks + speedClocks)
        return spread <= Self.maximumClockOffsetSpreadSeconds + Self.roundingToleranceSeconds ? .monotonic : .wallClock
    }

    /// 「実時間 − 単調時刻」のばらつき(最大 − 最小)を返します。
    ///
    /// 責務: 先頭の読みを基準にした差で各読みのずれを求め(大きな値どうしの引き算による桁落ちを避ける)、その幅を求めます。
    /// - Parameter readings: 時計の読み(1件以上)。
    /// - Returns: ばらつき(秒)。読みが無ければ 0。
    private static func offsetSpreadSeconds(of readings: [ClockReading]) -> Double {
        guard let reference = readings.first else { return 0 }
        let offsets = readings.map { reading in
            let wallDelta = reading.observedAt.timeIntervalSince(reference.observedAt)
            let monotonicDelta = Int64(bitPattern: reading.monotonicNanoseconds &- reference.monotonicNanoseconds)
            return wallDelta - Double(monotonicDelta) / nanosecondsPerSecond
        }
        guard let minimum = offsets.min(), let maximum = offsets.max() else { return 0 }
        return maximum - minimum
    }

    /// 1件のサンプルが持つ2つの時計の読みです。
    private struct ClockReading: Sendable {
        /// 実時間。
        let observedAt: Date
        /// 単調時計(ナノ秒)。
        let monotonicNanoseconds: UInt64
    }
}
