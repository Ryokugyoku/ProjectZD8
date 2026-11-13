/// 分析で使う基本統計です。
nonisolated enum AnalysisStatistics {
    /// 昇順に並んだ値の百分位数を線形補間(R-7法)で求めます。
    ///
    /// 責務: 並べ替え済みの値から指定割合の位置の値を返します。
    /// - Parameters:
    ///   - sorted: 昇順の値。空であってはなりません。
    ///   - fraction: 0〜1の割合。
    static func percentile(sorted: [Double], fraction: Double) -> Double {
        precondition(!sorted.isEmpty)
        if sorted.count == 1 { return sorted[0] }
        let position = min(max(fraction, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }

    /// 値の中央値・p05・p95を求めます。
    ///
    /// 責務: 並べ替えを伴う分位統計を1回の走査でまとめます。値が無ければ `nil` です。
    static func quantiles(of values: [Double]) -> (median: Double, p05: Double, p95: Double)? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return (
            percentile(sorted: sorted, fraction: 0.5),
            percentile(sorted: sorted, fraction: 0.05),
            percentile(sorted: sorted, fraction: 0.95)
        )
    }

    /// 値を小数第`places`位へ丸めます。
    ///
    /// 責務: JSONの大きさを抑えるため、表現に不要な桁を落とします。
    static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow10(places)
        return (value * scale).rounded() / scale
    }

    /// 責務: 10の整数乗を返します。
    private static func pow10(_ places: Int) -> Double {
        var result = 1.0
        for _ in 0..<places { result *= 10 }
        return result
    }
}
