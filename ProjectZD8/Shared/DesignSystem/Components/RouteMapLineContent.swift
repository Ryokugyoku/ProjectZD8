/// 地図部品に渡す線1本の契約です。機能側の線の型は Platform の Presentation で準拠させます。
protocol RouteMapLineContent: Identifiable where ID == Int {
    /// 線を描く座標の列です。
    var coordinates: [GeoCoordinate] { get }
    /// 線の見た目です。
    var appearance: RouteMapLineAppearance { get }
}
