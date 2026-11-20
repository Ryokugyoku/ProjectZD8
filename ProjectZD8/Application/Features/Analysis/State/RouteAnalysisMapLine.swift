/// 解析の地図に描く色の区間の線1本です。
nonisolated struct RouteAnalysisMapLine: Identifiable, Equatable, Sendable {
    /// 地図の中で一意な番号です。
    let id: Int
    /// 間引いた後の座標の列です。
    let coordinates: [GeoCoordinate]
    /// 線の色の分類です。
    let category: RouteAnalysisColorCategory
    /// 概略の位置の区間なら `true`(破線で描きます)です。
    let isApproximate: Bool
    /// 強調する時刻の範囲の線なら `true`(太く描きます)です。
    let isEmphasized: Bool
}
