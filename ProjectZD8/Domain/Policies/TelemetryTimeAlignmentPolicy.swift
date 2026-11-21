import Foundation

/// 位置と PID の値を同じ時間の軸へ載せる時に、どちらの時計を使うかを決めます。
///
/// 同じ起動中の記録なら単調時計が正しく、実時間の段差(時刻の補正や手動の変更)に強いので、単調時計を選びます。
/// 再起動を挟むと「実時間 − 単調秒」のばらつきが大きくなるので、実時間に倒します。
nonisolated struct TelemetryTimeAlignmentPolicy: Sendable {
    /// 単調時計を選べる「実時間 − 単調秒」のばらつき(最大 − 最小)の上限(秒、ちょうどを含む)です。
    private let maximumOffsetSpreadSeconds: TimeInterval

    /// ばらつきの上限を固定して生成します。
    ///
    /// 責務: 単調時計を選ぶ条件の上限を保持します。
    /// - Parameter maximumOffsetSpreadSeconds: 単調時計を選べるばらつきの上限(秒)。既定は 600。
    init(maximumOffsetSpreadSeconds: TimeInterval = 600) {
        self.maximumOffsetSpreadSeconds = maximumOffsetSpreadSeconds
    }

    /// 位置と値の時刻の組から、時計の選び方を決めます。
    ///
    /// 責務: 値が1件以上あり、位置も値もすべて単調時刻を持ち、全点の差のばらつきが上限以内なら、
    /// 値の差の中央値(偶数個なら下側)を差に使う単調時計を返します。それ以外は実時間を返します。
    /// - Parameters:
    ///   - locations: 位置の時刻の組。
    ///   - values: PID の値の時刻の組。
    /// - Returns: 時計の選び方。
    func alignment(locations: [TelemetryClockStamp], values: [TelemetryClockStamp]) -> TelemetryTimeAlignment {
        guard !locations.isEmpty,
              let valueOffsets = Self.offsets(of: values),
              let locationOffsets = Self.offsets(of: locations),
              let median = Self.lowerMedian(of: valueOffsets),
              isWithinSpread(valueOffsets + locationOffsets)
        else {
            return .wallClock
        }
        return .monotonic(referenceOffsetSeconds: median)
    }

    /// 差のばらつきが上限以内かを判定します。
    ///
    /// 責務: 差の最大と最小の幅を上限と比べます(上限ちょうどは以内)。
    /// - Parameter offsets: 差の列(空でない)。
    /// - Returns: 以内なら `true`。
    private func isWithinSpread(_ offsets: [Double]) -> Bool {
        guard let minimum = offsets.min(), let maximum = offsets.max() else {
            return false
        }
        return maximum - minimum <= maximumOffsetSpreadSeconds
    }

    /// 各時刻の組の「実時間(参照日からの秒) − 単調秒」を求めます。
    ///
    /// 責務: すべての組が単調時刻を持つ時だけ差の列を返します。
    /// - Parameter stamps: 時刻の組。
    /// - Returns: 差の列。空、または単調時刻の無い組がある時は `nil`。
    private static func offsets(of stamps: [TelemetryClockStamp]) -> [Double]? {
        guard !stamps.isEmpty else {
            return nil
        }
        var offsets: [Double] = []
        offsets.reserveCapacity(stamps.count)
        for stamp in stamps {
            guard let nanoseconds = stamp.monotonicNanoseconds else {
                return nil
            }
            offsets.append(stamp.observedAt.timeIntervalSinceReferenceDate - Double(nanoseconds) / 1_000_000_000)
        }
        return offsets
    }

    /// 中央値(偶数個なら下側)を求めます。
    ///
    /// 責務: 昇順に並べた列の `(count - 1) / 2` 番目を返します。
    /// - Parameter values: 値の列。
    /// - Returns: 中央値。空なら `nil`。
    private static func lowerMedian(of values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }
}
