/// 解析の地図に描く内容(線・印・表示範囲・凡例)です。
nonisolated struct RouteAnalysisMapLayers: Equatable, Sendable {
    /// 色の区間ごとの線です。
    let lines: [RouteAnalysisMapLine]
    /// 端の印です。
    let markers: [RouteAnalysisMapMarker]
    /// 描ける点をすべて含む外接矩形です。点が無ければ `nil` です。
    let bounds: GeoBoundingBox?
    /// 凡例の項目です。
    let legend: [RouteAnalysisLegendEntry]
    /// 値が無い辺が1つ以上ある時に `true` です。
    let hasNoValueEdges: Bool
    /// 値が対応した点が1つ以上ある時に `true` です。
    let hasMatchedValues: Bool
}
