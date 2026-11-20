/// 地図に描く走行ルートの折れ線1本です。
nonisolated struct DrivingRouteMapPolyline: Identifiable, Equatable, Sendable {
    /// 地図の中で一意な番号です。
    let id: Int
    /// 間引いた後の座標の列です。
    let coordinates: [GeoCoordinate]
    /// 概略の位置の区間なら `true`(破線で描きます)です。
    let isApproximate: Bool
}
