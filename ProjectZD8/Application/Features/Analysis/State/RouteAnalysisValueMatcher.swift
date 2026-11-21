import Foundation

/// 指定の時刻に対応する指標の値を、値の列から最近傍で選びます。
///
/// 色は区分の離散値なので補間はしません。時刻の差が許容差を超える時は値なしにします。
nonisolated struct RouteAnalysisValueMatcher: Sendable {
    /// 値を対応づける時刻の差の上限(秒、ちょうどを含む)です。
    private let toleranceSeconds: TimeInterval

    /// 時刻の差の許容差を固定して生成します。
    ///
    /// 責務: 値を対応づける許容差を保持します。
    /// - Parameter toleranceSeconds: 時刻の差の上限(秒)。既定は 2.0。
    init(toleranceSeconds: TimeInterval = 2.0) {
        self.toleranceSeconds = toleranceSeconds
    }

    /// 指定の時刻に最も近い値を返します。
    ///
    /// 責務: 二分探索で前後の値を求め、時刻の差が許容差以内の近い方を選びます。
    /// 等距離なら時刻の早い方、同じ時刻の値が複数あれば列の最初の値を選びます。
    /// - Parameters:
    ///   - date: 探す時刻。
    ///   - series: `date` の昇順の値の列。
    /// - Returns: 値。列が空、または最も近い値でも許容差を超える時は `nil`。
    func value(at date: Date, in series: RouteAnalysisValueSeries) -> Double? {
        let samples = series.samples
        let upper = firstIndex(in: samples, notBefore: date)
        var candidates: [Int] = []
        if upper > 0 {
            candidates.append(firstIndex(in: samples, notBefore: samples[upper - 1].date))
        }
        if upper < samples.count {
            candidates.append(upper)
        }
        guard let nearest = candidates.min(by: { gap(samples[$0], date) < gap(samples[$1], date) }),
              gap(samples[nearest], date) <= toleranceSeconds
        else {
            return nil
        }
        return samples[nearest].value
    }

    /// 時刻が指定の時刻以降である最初の値の位置を返します。
    ///
    /// 責務: `date` の昇順を前提に二分探索します。
    /// - Parameters:
    ///   - samples: `date` の昇順の値。
    ///   - date: 基準の時刻。
    /// - Returns: 該当する最初の位置。すべて前なら `samples.count`。
    private func firstIndex(in samples: [RouteAnalysisValueSample], notBefore date: Date) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].date < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// 値の時刻と指定の時刻の差を返します。
    ///
    /// 責務: 前後を問わない時刻の差の絶対値を求めます。
    /// - Parameters:
    ///   - sample: 値。
    ///   - date: 比べる時刻。
    /// - Returns: 差(秒、0 以上)。
    private func gap(_ sample: RouteAnalysisValueSample, _ date: Date) -> TimeInterval {
        abs(sample.date.timeIntervalSince(date))
    }
}
