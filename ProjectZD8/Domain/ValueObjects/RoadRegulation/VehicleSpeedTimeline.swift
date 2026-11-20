import Foundation

/// 車速の時系列です。時刻の昇順に並び、同じ時刻のサンプルは後に渡された値だけを残します。
nonisolated struct VehicleSpeedTimeline: Equatable, Sendable {
    /// 時刻の昇順・時刻の重複なしのサンプル。
    let samples: [VehicleSpeedSample]

    /// サンプルを並べ直して時系列を作ります。
    ///
    /// 責務: 時刻か車速が有限でないサンプルを除き、時刻の昇順に安定に並べ、同じ時刻は後の値だけを残します。
    /// - Parameter samples: 任意の順のサンプル。
    init(samples: [VehicleSpeedSample]) {
        let ordered = samples.enumerated()
            .filter { $0.element.time.isFinite && $0.element.kph.isFinite }
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element)
        self.samples = Self.keepingLastOfEqualTimes(ordered)
    }

    /// サンプルが1つも無いかどうかです。
    var isEmpty: Bool {
        samples.isEmpty
    }

    /// 時刻の範囲(両端を含む)にあるサンプルを返します。
    ///
    /// 責務: 二分探索で範囲の両端の位置を求め、その間を切り出します。
    /// - Parameter range: 時刻の範囲。
    /// - Returns: 範囲内のサンプル(時刻の昇順)。無ければ空。
    func samples(in range: ClosedRange<TimeInterval>) -> ArraySlice<VehicleSpeedSample> {
        let lower = partitionIndex { $0.time >= range.lowerBound }
        let upper = partitionIndex { $0.time > range.upperBound }
        return samples[lower..<Swift.max(lower, upper)]
    }

    /// 指定時刻以前で最後のサンプルを返します。
    ///
    /// 責務: 時刻がちょうど同じサンプルを含めて、直前のサンプルを探します。
    /// - Parameter time: 基準の時刻。
    /// - Returns: 無ければ `nil`。
    func lastSample(atOrBefore time: TimeInterval) -> VehicleSpeedSample? {
        let index = partitionIndex { $0.time > time }
        return index > 0 ? samples[index - 1] : nil
    }

    /// 指定時刻以後で最初のサンプルを返します。
    ///
    /// 責務: 時刻がちょうど同じサンプルを含めて、直後のサンプルを探します。
    /// - Parameter time: 基準の時刻。
    /// - Returns: 無ければ `nil`。
    func firstSample(atOrAfter time: TimeInterval) -> VehicleSpeedSample? {
        let index = partitionIndex { $0.time >= time }
        return index < samples.count ? samples[index] : nil
    }

    /// 条件を初めて満たすサンプルの位置を返します。
    ///
    /// 責務: 時刻の昇順で単調な条件(前半は偽、後半は真)の境目を二分探索で求めます。
    /// - Parameter isInUpperPart: 後半であることの判定。
    /// - Returns: 境目の位置。すべて偽なら `samples.count`。
    private func partitionIndex(where isInUpperPart: (VehicleSpeedSample) -> Bool) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if isInUpperPart(samples[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    /// 時刻の昇順に並んだサンプルから、同じ時刻の後の値だけを残します。
    ///
    /// 責務: 隣り合う同じ時刻のサンプルを、後に現れたものへ置き換えます。
    /// - Parameter ordered: 時刻の昇順で、同じ時刻は渡された順に並んだサンプル。
    /// - Returns: 時刻の重複がないサンプル。
    private static func keepingLastOfEqualTimes(_ ordered: [VehicleSpeedSample]) -> [VehicleSpeedSample] {
        var result: [VehicleSpeedSample] = []
        result.reserveCapacity(ordered.count)
        for sample in ordered {
            if result.last?.time == sample.time {
                result[result.count - 1] = sample
            } else {
                result.append(sample)
            }
        }
        return result
    }
}
