/// 位置の連番の範囲と、その範囲の色の分類の組です。値の色分けも重ね合わせも同じ形で表します。
nonisolated struct RouteAnalysisColorRun: Equatable, Sendable {
    /// 位置のサンプルの連番の範囲(両端を含む)です。
    let sequenceRange: ClosedRange<Int64>
    /// 範囲に付ける色の分類です。
    let category: RouteAnalysisColorCategory
}
