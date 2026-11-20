import Foundation

/// 多角形(輪)の内外判定と、境界までの距離を求めます。
nonisolated struct GeoPolygonCalculator: Sendable {
    /// 境界までの距離に使う、点と線の近さの計算器です。
    private let proximityCalculator = GeoPolylineProximityCalculator()

    /// 状態を持たない計算器を作ります。
    ///
    /// 責務: 定数だけで計算する多角形の計算器を構築します。
    init() {}

    /// 点が輪の内側にあるかを偶奇判定で返します。
    ///
    /// 責務: 点から東へ伸ばした半直線が横切る辺の数を数えます。閉じていない輪は最後と最初の点を結んで閉じます。
    /// - Parameters:
    ///   - point: 調べる点。
    ///   - ring: 輪の点の列(閉じていても閉じていなくてもよい)。
    /// - Returns: 横切る辺の数が奇数なら `true`。点が3つ未満なら `false`。
    func contains(_ point: GeoCoordinate, ring: [GeoCoordinate]) -> Bool {
        guard ring.count >= 3 else { return false }
        var isInside = false
        var previous = ring[ring.count - 1]
        for current in ring {
            if crossesEastwardRay(from: point, edgeStart: previous, edgeEnd: current) {
                isInside.toggle()
            }
            previous = current
        }
        return isInside
    }

    /// 点から輪の境界までの距離(m)を返します。
    ///
    /// 責務: 輪を閉じた線とみなし、全辺の点–線分距離の最小値を求めます。
    /// - Parameters:
    ///   - point: 調べる点。
    ///   - ring: 輪の点の列(閉じていても閉じていなくてもよい)。
    /// - Returns: 境界までの距離。長さのある辺が無ければ `nil`。
    func distanceToBoundaryMeters(_ point: GeoCoordinate, ring: [GeoCoordinate]) -> Double? {
        proximityCalculator.nearest(to: point, on: closed(ring))?.distanceMeters
    }

    /// 輪の最後に最初の点を足して閉じます。
    ///
    /// 責務: 既に閉じている輪と空の輪はそのまま返します。
    /// - Parameter ring: 輪の点の列。
    /// - Returns: 閉じた点の列。
    private func closed(_ ring: [GeoCoordinate]) -> [GeoCoordinate] {
        guard let first = ring.first, ring.last != first else { return ring }
        return ring + [first]
    }

    /// 1つの辺が、点から東へ伸ばした半直線を横切るかを返します。
    ///
    /// 責務: 辺が点の緯度をまたぎ、その緯度での辺の経度が点より東にあることを判定します。
    /// - Parameters:
    ///   - point: 半直線の始点。
    ///   - edgeStart: 辺の始点。
    ///   - edgeEnd: 辺の終点。
    /// - Returns: 横切るなら `true`。
    private func crossesEastwardRay(from point: GeoCoordinate, edgeStart: GeoCoordinate, edgeEnd: GeoCoordinate) -> Bool {
        guard (edgeStart.latitude > point.latitude) != (edgeEnd.latitude > point.latitude) else { return false }
        let ratio = (point.latitude - edgeStart.latitude) / (edgeEnd.latitude - edgeStart.latitude)
        let crossingLongitude = edgeStart.longitude + ratio * (edgeEnd.longitude - edgeStart.longitude)
        return point.longitude < crossingLongitude
    }
}
