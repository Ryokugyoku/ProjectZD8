import Foundation

/// 原点の緯度を基準にした正距円筒の近似で、座標と局所平面(m)を相互に変換します。
nonisolated struct GeoLocalProjection: Sendable {
    /// 平面の原点にする座標です。
    let origin: GeoCoordinate
    /// 経度1度あたりの東西方向の距離(m)= cos(原点の緯度)·k です。
    private let metersPerLongitudeDegree: Double

    /// 原点を決めて投影を作ります。
    ///
    /// 責務: 原点の緯度での経度1度あたりの距離を先に求めておきます。
    /// - Parameter origin: 平面の原点にする座標。
    init(origin: GeoCoordinate) {
        self.origin = origin
        self.metersPerLongitudeDegree = cos(origin.latitude * Double.pi / 180) * GeoBoundingBox.metersPerDegree
    }

    /// 座標を平面上の点へ投影します。
    ///
    /// 責務: x = (経度 − 原点の経度)·cos(原点の緯度)·k、y = (緯度 − 原点の緯度)·k を求めます。
    /// - Parameter coordinate: 投影する座標。
    /// - Returns: 東が +x、北が +y(m)の点。
    func project(_ coordinate: GeoCoordinate) -> GeoPlanarPoint {
        GeoPlanarPoint(
            x: (coordinate.longitude - origin.longitude) * metersPerLongitudeDegree,
            y: (coordinate.latitude - origin.latitude) * GeoBoundingBox.metersPerDegree
        )
    }

    /// 平面上の点を座標へ戻します。
    ///
    /// 責務: `project` の逆の計算をし、座標として有効な値だけを返します。
    /// - Parameter point: 戻す点(m)。
    /// - Returns: 座標。範囲外・有限でない値になる時(極付近の原点を含む)は `nil`。
    func unproject(_ point: GeoPlanarPoint) -> GeoCoordinate? {
        GeoCoordinate(
            latitude: origin.latitude + point.y / GeoBoundingBox.metersPerDegree,
            longitude: origin.longitude + point.x / metersPerLongitudeDegree
        )
    }
}
