/// 地図に置く走行ルートの端の印です。
nonisolated struct DrivingRouteMapMarker: Identifiable, Equatable, Sendable {
    /// 地図の中で一意な番号です。
    let id: Int
    /// 印を置く座標です。
    let coordinate: GeoCoordinate
    /// 始点か終点かです。
    let endpoint: DrivingRouteEndpoint
}
