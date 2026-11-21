import Foundation

/// 正距円筒の近似で2点間の距離と方位を求めます(10 km 以内で誤差0.1%未満)。
///
/// 1度あたりの距離 k は `GeoBoundingBox.metersPerDegree`(6,371,008.8 m × π / 180 = 111,195.08 m)です。
nonisolated struct GeoDistanceCalculator: Sendable {
    /// 状態を持たない計算器を作ります。
    ///
    /// 責務: 定数だけで計算する距離計算器を構築します。
    init() {}

    /// 2点間の距離(m)を返します。
    ///
    /// 責務: 基準緯度を2点の平均とし、x = Δ経度·cos(平均緯度)·k、y = Δ緯度·k の長さを求めます。
    /// - Parameters:
    ///   - a: 1点目。
    ///   - b: 2点目。
    /// - Returns: 距離(m)。
    func distanceMeters(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let offset = planarOffset(from: a, to: b)
        return (offset.x * offset.x + offset.y * offset.y).squareRoot()
    }

    /// a から b へ向かう方位(度)を返します。
    ///
    /// 責務: atan2(x, y) を度へ直し、北0・時計回りの 0..<360 にそろえます。
    /// - Parameters:
    ///   - a: 出発点。
    ///   - b: 到着点。
    /// - Returns: 0..<360 の方位。2点が同じなら `nil`。
    func bearingDegrees(from a: GeoCoordinate, to b: GeoCoordinate) -> Double? {
        let offset = planarOffset(from: a, to: b)
        guard offset.x != 0 || offset.y != 0 else { return nil }
        return Self.normalizedDegrees(atan2(offset.x, offset.y) * 180 / Double.pi)
    }

    /// 2つの方位の差(度)を返します。
    ///
    /// 責務: |a − b| を360で割った余り r から min(r, 360 − r) を求めます。
    /// - Parameters:
    ///   - a: 1つ目の方位(度)。
    ///   - b: 2つ目の方位(度)。
    /// - Returns: 0...180 の差。
    func angularDifference(_ a: Double, _ b: Double) -> Double {
        let remainder = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(remainder, 360 - remainder)
    }

    /// a を原点とした b の平面上の位置(m)を返します。
    ///
    /// 責務: 2点の平均緯度を基準に、経度差と緯度差をメートルへ直します。
    /// - Parameters:
    ///   - a: 原点にする点。
    ///   - b: 位置を求める点。
    /// - Returns: 東が +x、北が +y の位置。
    private func planarOffset(from a: GeoCoordinate, to b: GeoCoordinate) -> GeoPlanarPoint {
        let meanLatitudeRadians = (a.latitude + b.latitude) / 2 * Double.pi / 180
        let k = GeoBoundingBox.metersPerDegree
        return GeoPlanarPoint(
            x: (b.longitude - a.longitude) * cos(meanLatitudeRadians) * k,
            y: (b.latitude - a.latitude) * k
        )
    }

    /// 角度を 0..<360 にそろえます。
    ///
    /// 責務: 負の角度に360を足し、丸めで360ちょうどになった値を0にします。
    /// - Parameter degrees: -180...180 の角度。
    /// - Returns: 0..<360 の角度。
    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let shifted = degrees < 0 ? degrees + 360 : degrees
        return shifted >= 360 ? 0 : shifted
    }
}
