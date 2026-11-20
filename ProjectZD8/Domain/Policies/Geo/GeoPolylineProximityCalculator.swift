import Foundation

/// 点と線(点の列)の近さを、点を中心にした局所平面で求めます。
nonisolated struct GeoPolylineProximityCalculator: Sendable {
    /// 線分の長さと方位を求める計算器です。
    private let distanceCalculator = GeoDistanceCalculator()

    /// 状態を持たない計算器を作ります。
    ///
    /// 責務: 定数だけで計算する近さの計算器を構築します。
    init() {}

    /// 点に最も近い線分の近さを返します。
    ///
    /// 責務: 線分ごとの近さから距離が最小のもの(同じ距離なら番号が小さいもの)を選びます。
    /// - Parameters:
    ///   - point: 調べる点。
    ///   - polyline: 線の点の列。
    /// - Returns: 最も近い線分の近さ。点が2つ未満、または長さ0の線分しか無ければ `nil`。
    func nearest(to point: GeoCoordinate, on polyline: [GeoCoordinate]) -> GeoPolylineProximity? {
        nearestSegments(to: point, on: polyline).min { $0.distanceMeters < $1.distanceMeters }
    }

    /// 線分ごとの近さを線分の番号順に返します。
    ///
    /// 責務: 長さ0の線分を飛ばし、各線分の最近点・方位・長さ・始点からの距離を求めます。
    /// - Parameters:
    ///   - point: 調べる点。
    ///   - polyline: 線の点の列。
    /// - Returns: 長さが0でない線分ごとの近さ。点が2つ未満なら空。
    func nearestSegments(to point: GeoCoordinate, on polyline: [GeoCoordinate]) -> [GeoPolylineProximity] {
        guard polyline.count >= 2 else { return [] }
        let projection = GeoLocalProjection(origin: point)
        var results: [GeoPolylineProximity] = []
        var alongBeforeSegment = 0.0
        for index in 0..<(polyline.count - 1) {
            let start = polyline[index]
            let end = polyline[index + 1]
            let length = distanceCalculator.distanceMeters(start, end)
            if let proximity = proximity(
                segmentIndex: index,
                start: projection.project(start),
                end: projection.project(end),
                geographic: (start, end),
                alongBeforeSegment: alongBeforeSegment
            ) {
                results.append(proximity)
            }
            alongBeforeSegment += length
        }
        return results
    }

    /// 線の全長(m)を返します。
    ///
    /// 責務: 隣り合う点の距離を合計します。
    /// - Parameter polyline: 線の点の列。
    /// - Returns: 全長。点が2つ未満なら0。
    func pathLengthMeters(_ polyline: [GeoCoordinate]) -> Double {
        zip(polyline, polyline.dropFirst()).reduce(0) { total, pair in
            total + distanceCalculator.distanceMeters(pair.0, pair.1)
        }
    }

    /// 原点(調べる点)から1つの線分までの近さを求めます。
    ///
    /// 責務: t = 内積 / 長さ² を 0...1 に切り詰めて最近点までの距離を求め、線分の方位・長さと合わせます。
    /// - Parameters:
    ///   - segmentIndex: 線分の番号。
    ///   - start: 投影した始点(m)。
    ///   - end: 投影した終点(m)。
    ///   - geographic: 始点と終点の座標(方位と長さの計算用)。
    ///   - alongBeforeSegment: 線の始点からこの線分の始点までの距離(m)。
    /// - Returns: 近さ。長さ0の線分なら `nil`。
    private func proximity(
        segmentIndex: Int,
        start: GeoPlanarPoint,
        end: GeoPlanarPoint,
        geographic: (start: GeoCoordinate, end: GeoCoordinate),
        alongBeforeSegment: Double
    ) -> GeoPolylineProximity? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 0,
              let bearing = distanceCalculator.bearingDegrees(from: geographic.start, to: geographic.end)
        else { return nil }
        let rawFraction = -(start.x * dx + start.y * dy) / squaredLength
        let fraction = min(1, max(0, rawFraction))
        let closestX = start.x + fraction * dx
        let closestY = start.y + fraction * dy
        let segmentLength = distanceCalculator.distanceMeters(geographic.start, geographic.end)
        return GeoPolylineProximity(
            segmentIndex: segmentIndex,
            distanceMeters: (closestX * closestX + closestY * closestY).squareRoot(),
            fraction: fraction,
            segmentBearingDegrees: bearing,
            segmentLengthMeters: segmentLength,
            alongMetersFromStart: alongBeforeSegment + fraction * segmentLength
        )
    }
}
