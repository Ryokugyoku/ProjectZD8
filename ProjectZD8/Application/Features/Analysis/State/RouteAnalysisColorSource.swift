/// 走行ルートの色分けの元(指標か重ね合わせ)です。
nonisolated enum RouteAnalysisColorSource: Hashable, Sendable {
    /// 記録した値の指標で色分けします。
    case metric(RouteAnalysisColorMetric)
    /// 識別子で指す重ね合わせで色分けします。
    case overlay(id: String)
}
