/// 地図に描く走行ルートの形(折れ線・印・表示範囲)です。
nonisolated struct DrivingRouteMapGeometry: Equatable, Sendable {
    /// 描く折れ線です。
    let polylines: [DrivingRouteMapPolyline]
    /// 端の印です。
    let markers: [DrivingRouteMapMarker]
    /// 描ける点をすべて含む外接矩形です。
    let bounds: GeoBoundingBox
}
