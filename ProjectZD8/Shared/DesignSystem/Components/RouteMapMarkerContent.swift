/// 地図部品に渡す端の印1つの契約です。機能側の印の型は Platform の Presentation で準拠させます。
protocol RouteMapMarkerContent: Identifiable where ID == Int {
    /// 印を置く座標です。
    var coordinate: GeoCoordinate { get }
    /// 始点か終点かです。
    var endpoint: DrivingRouteEndpoint { get }
}
