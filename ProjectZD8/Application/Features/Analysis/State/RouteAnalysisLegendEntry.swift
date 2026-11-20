/// 地図の凡例の1項目です。
nonisolated struct RouteAnalysisLegendEntry: Identifiable, Equatable, Sendable {
    /// 凡例の中で一意な番号(表示順)です。
    let id: Int
    /// 項目の色の分類です。
    let category: RouteAnalysisColorCategory
    /// 項目の文字(範囲の数値と単位など)です。
    let text: String
}
