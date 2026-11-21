/// 解析のルートのグラフ1つ分の系列です。
nonisolated struct RouteAnalysisChartSeries: Equatable, Sendable {
    /// グラフの名前のローカライズキーです。
    let titleKey: String
    /// 値の単位です。
    let unit: String
    /// 時刻順に並んだ点です。
    let points: [RouteAnalysisChartPoint]
    /// 値の最小です。
    let minimum: Double
    /// 値の最大です。
    let maximum: Double
}
