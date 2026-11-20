import Foundation

/// 時刻の昇順に並べた走行ルートの点と、その時刻を揃えた時計の選び方です。
nonisolated struct RouteAnalysisTimeline: Equatable, Sendable {
    /// `date` の昇順に並んだ点です。
    let points: [RouteAnalysisTimelinePoint]
    /// 点の時刻を揃えた時計の選び方です。
    let alignment: TelemetryTimeAlignment

    /// 指定の時刻に最も近い点の位置を返します。
    ///
    /// 責務: 二分探索で前後の点を求め、時刻の差が許容差以内の近い方(等距離なら前)を選びます。
    /// - Parameters:
    ///   - date: 探す時刻。
    ///   - tolerance: 許す時刻の差(秒、ちょうどを含む)。
    /// - Returns: `points` の中の位置。点が無い、または最も近い点でも許容差を超える時は `nil`。
    func nearestPointIndex(to date: Date, within tolerance: TimeInterval) -> Int? {
        let upper = firstIndex(notBefore: date)
        let candidates = [upper - 1, upper].filter { points.indices.contains($0) }
        guard let nearest = candidates.min(by: { gap($0, date) < gap($1, date) }) else { return nil }
        return gap(nearest, date) <= tolerance ? nearest : nil
    }

    /// 時刻が指定の時刻以降である最初の点の位置を返します。
    ///
    /// 責務: `date` の昇順を前提に二分探索します。
    /// - Parameter date: 基準の時刻。
    /// - Returns: 該当する最初の位置。すべて前なら `points.count`。
    private func firstIndex(notBefore date: Date) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].date < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    /// 点の時刻と指定の時刻の差を返します。
    ///
    /// 責務: 前後を問わない時刻の差の絶対値を求めます。
    /// - Parameters:
    ///   - index: 点の位置。
    ///   - date: 比べる時刻。
    /// - Returns: 差(秒、0 以上)。
    private func gap(_ index: Int, _ date: Date) -> TimeInterval {
        abs(points[index].date.timeIntervalSince(date))
    }
}
