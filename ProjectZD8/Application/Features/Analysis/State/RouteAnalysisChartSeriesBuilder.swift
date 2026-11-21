import Foundation

/// 指標の値の列と走行ルートの標高を、グラフ用の点列にします。
///
/// - 時刻の差が切れ目の秒数を超えたら線を分けます(`lineID` を進めます)。位置の途切れと揃えるためです。
/// - 点が上限を超える時は、時刻順に等分した区間ごとに最小と最大の点を残して間引きます(山と谷を残します)。
nonisolated struct RouteAnalysisChartSeriesBuilder: Sendable {
    /// 線の番号を付けた、間引く前の点です。
    private typealias LinedValue = (date: Date, value: Double, lineID: Int)

    /// 標高のグラフの名前のローカライズキーです。
    private static let elevationTitleKey = "analysis.route.elevation.title"
    /// 標高の単位です(ローカライズしません)。
    private static let elevationUnit = "m"

    /// 1つのグラフの点の上限です。
    private let maximumPointCount: Int
    /// 線を分ける時刻の差(秒。ちょうどはつなぎます)です。
    private let lineBreakSeconds: TimeInterval

    /// 点の上限と線の切れ目を固定して生成します。
    ///
    /// 責務: 間引きと線の分け方に使う値を保持します。
    /// - Parameters:
    ///   - maximumPointCount: 1つのグラフの点の上限。既定は 600。
    ///   - lineBreakSeconds: 線を分ける時刻の差(秒)。既定は 10。
    init(maximumPointCount: Int = 600, lineBreakSeconds: TimeInterval = 10) {
        self.maximumPointCount = maximumPointCount
        self.lineBreakSeconds = lineBreakSeconds
    }

    /// 指標の値の列をグラフの系列にします。
    ///
    /// 責務: 名前は指標のキー、単位は列の単位(無ければ指標の代わりの単位)にし、線を分けて間引きます。
    /// - Parameters:
    ///   - series: `date` の昇順の値の列。
    ///   - metric: 値の指標。
    /// - Returns: グラフの系列。列が空なら `nil`。
    func metricSeries(_ series: RouteAnalysisValueSeries, metric: RouteAnalysisColorMetric) -> RouteAnalysisChartSeries? {
        let values = series.samples.map { (date: $0.date, value: $0.value) }
        return chartSeries(titleKey: metric.titleKey, unit: series.unit ?? metric.fallbackUnit, values: values, minimumCount: 1)
    }

    /// 時間の軸の標高をグラフの系列にします。
    ///
    /// 責務: 標高のある点だけを時刻順に使い、線を分けて間引きます。
    /// - Parameter timeline: 時間の軸。
    /// - Returns: グラフの系列。標高のある点が2つ未満なら `nil`。
    func elevationSeries(_ timeline: RouteAnalysisTimeline) -> RouteAnalysisChartSeries? {
        let values = timeline.points.compactMap { point in point.altitudeMeters.map { (date: point.date, value: $0) } }
        return chartSeries(titleKey: Self.elevationTitleKey, unit: Self.elevationUnit, values: values, minimumCount: 2)
    }

    /// 時刻順の値をグラフの系列にします。
    ///
    /// 責務: 点の数を確かめ、線を分け、間引き、全体の最小と最大を求めます。
    /// - Parameters:
    ///   - titleKey: グラフの名前のキー。
    ///   - unit: 値の単位。
    ///   - values: 時刻順の値。
    ///   - minimumCount: 系列にするのに要る点の数。
    /// - Returns: グラフの系列。点が足りなければ `nil`。
    private func chartSeries(
        titleKey: String,
        unit: String,
        values: [(date: Date, value: Double)],
        minimumCount: Int
    ) -> RouteAnalysisChartSeries? {
        guard values.count >= max(minimumCount, 1),
              let minimum = values.lazy.map(\.value).min(),
              let maximum = values.lazy.map(\.value).max()
        else {
            return nil
        }
        let points = decimated(lined(values)).enumerated().map { offset, point in
            RouteAnalysisChartPoint(id: offset, date: point.date, value: point.value, lineID: point.lineID)
        }
        return RouteAnalysisChartSeries(titleKey: titleKey, unit: unit, points: points, minimum: minimum, maximum: maximum)
    }

    /// 時刻順の値に線の番号を付けます。
    ///
    /// 責務: 直前の点との時刻の差が切れ目の秒数を超えるたびに線の番号を1つ進めます。
    /// - Parameter values: 時刻順の値。
    /// - Returns: 線の番号を付けた値。
    private func lined(_ values: [(date: Date, value: Double)]) -> [LinedValue] {
        var lineID = 0
        var previousDate: Date?
        return values.map { item in
            if let previousDate, item.date.timeIntervalSince(previousDate) > lineBreakSeconds {
                lineID += 1
            }
            previousDate = item.date
            return (item.date, item.value, lineID)
        }
    }

    /// 点を上限以下に間引きます。
    ///
    /// 責務: 上限以下ならそのまま返し、超える時は時刻順に等分した区間ごとに最小と最大の点を時刻順に残します。
    /// 上限が2未満の時は、先頭から上限の数だけ残します。
    /// - Parameter values: 線の番号を付けた時刻順の値。
    /// - Returns: 間引いた値(時刻順)。
    private func decimated(_ values: [LinedValue]) -> [LinedValue] {
        guard values.count > maximumPointCount else {
            return values
        }
        guard maximumPointCount >= 2 else {
            return Array(values.prefix(max(maximumPointCount, 0)))
        }
        let bucketCount = maximumPointCount / 2
        var kept: [LinedValue] = []
        kept.reserveCapacity(maximumPointCount)
        for bucket in 0..<bucketCount {
            let range = (bucket * values.count / bucketCount)..<((bucket + 1) * values.count / bucketCount)
            kept.append(contentsOf: extremes(of: values, in: range))
        }
        return kept
    }

    /// 1つの区間の最小と最大の点を時刻順に返します。
    ///
    /// 責務: 区間の中で値が最小の点と最大の点(同じ値なら先の点)を選び、同じ点なら1つにします。
    /// - Parameters:
    ///   - values: 線の番号を付けた時刻順の値。
    ///   - range: 区間の位置の範囲。
    /// - Returns: 残す点(0〜2個、時刻順)。
    private func extremes(of values: [LinedValue], in range: Range<Int>) -> [LinedValue] {
        guard let minimumIndex = range.min(by: { values[$0].value < values[$1].value }),
              let maximumIndex = range.max(by: { values[$0].value < values[$1].value })
        else {
            return []
        }
        if minimumIndex == maximumIndex {
            return [values[minimumIndex]]
        }
        return [min(minimumIndex, maximumIndex), max(minimumIndex, maximumIndex)].map { values[$0] }
    }
}
