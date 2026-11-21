import Foundation
@testable import ProjectZD8

/// テストで「メートル単位の形状」を座標へ直す補助です。製品の `GeoLocalProjection` に頼らず、式だけで独立に計算します。
struct GeoTestCoordinates {
    /// 1度あたりの距離(m)。6,371,008.8 m × π / 180。
    static let metersPerDegree = 111_195.080_233_532_92

    /// 原点の緯度(度)。
    let originLatitude: Double
    /// 原点の経度(度)。
    let originLongitude: Double

    /// 沖縄本島付近を原点にした補助を作ります。
    ///
    /// 責務: 既定の原点(北緯26.2度、東経127.7度)で補助を構築します。
    init(originLatitude: Double = 26.2, originLongitude: Double = 127.7) {
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
    }

    /// 原点から東へ x m、北へ y m の座標を返します。
    ///
    /// 責務: 緯度 = 原点 + y / k、経度 = 原点 + x / (k × cos(原点の緯度)) を求めます。
    /// - Parameters:
    ///   - x: 東向きの距離(m)。
    ///   - y: 北向きの距離(m)。
    /// - Returns: 座標。範囲外になる値を渡した時はテストの誤りとして停止します。
    func point(x: Double, y: Double) -> GeoCoordinate {
        let metersPerLongitudeDegree = Self.metersPerDegree * cos(originLatitude * Double.pi / 180)
        guard let coordinate = GeoCoordinate(
            latitude: originLatitude + y / Self.metersPerDegree,
            longitude: originLongitude + x / metersPerLongitudeDegree
        ) else {
            preconditionFailure("テストの座標が範囲外です")
        }
        return coordinate
    }

    /// (x, y) の列を座標の列へ直します。
    ///
    /// 責務: `point(x:y:)` を順に適用します。
    /// - Parameter meters: メートル単位の点の列。
    /// - Returns: 座標の列。
    func points(_ meters: [(x: Double, y: Double)]) -> [GeoCoordinate] {
        meters.map { point(x: $0.x, y: $0.y) }
    }
}
