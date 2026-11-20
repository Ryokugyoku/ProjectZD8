import Foundation
@testable import ProjectZD8

/// 間引きのテストで、ジグザグ・直線・円弧の折れ線をメートル単位から作る補助です(型推論を軽くするため明示的な反復で作ります)。
enum GeoPolylineFixtures {
    private static let geo = GeoTestCoordinates()

    /// 東向きに等間隔で並び、北向きが交互に 0 と amplitude になる折れ線を作ります。
    ///
    /// 責務: 偶数番目は y = baseY、奇数番目は y = baseY + amplitude の点を count 個返します。
    /// - Parameters:
    ///   - count: 点の数。
    ///   - step: 東向きの間隔(m)。
    ///   - amplitude: 奇数番目の点の北向きのずれ(m)。
    ///   - baseY: 北向きの基準(m)。
    /// - Returns: 座標の列。
    static func zigzag(count: Int, step: Double, amplitude: Double, baseY: Double = 0) -> [GeoCoordinate] {
        var result: [GeoCoordinate] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let x: Double = Double(index) * step
            let y: Double = baseY + (index % 2 == 0 ? 0 : amplitude)
            result.append(geo.point(x: x, y: y))
        }
        return result
    }

    /// 原点を中心に半径 radius の円弧(0 から 270 度)を作ります。
    ///
    /// 責務: 角度を等間隔に刻んだ点を count 個返します。
    /// - Parameters:
    ///   - count: 点の数。
    ///   - radius: 半径(m)。
    /// - Returns: 座標の列。
    static func arc(count: Int, radius: Double) -> [GeoCoordinate] {
        var result: [GeoCoordinate] = []
        for index in 0..<count {
            let angle: Double = Double(index) / Double(count - 1) * 1.5 * Double.pi
            result.append(geo.point(x: radius * cos(angle), y: radius * sin(angle)))
        }
        return result
    }
}
