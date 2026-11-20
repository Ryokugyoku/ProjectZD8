/// 地図の線の色分けの方法です。
nonisolated enum RouteAnalysisColoring: Equatable, Sendable {
    /// 色分けしません(基本の色)。
    case none
    /// 指標の値の列で色分けします。
    case metric(RouteAnalysisColorMetric, RouteAnalysisValueSeries)
    /// 重ね合わせの分類で色分けします。
    case overlay(RouteAnalysisOverlay)
}
