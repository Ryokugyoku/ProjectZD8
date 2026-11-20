import Foundation
@testable import ProjectZD8

/// 走行ルート(区間・点)を秒とメートルから直接組み立てるテストの補助です。
enum DrivingRoutePointFixtures {
    /// 走行ルートの1点を作ります。
    ///
    /// 責務: 原点から東へ x m、北へ y m の座標と、基準日時から `seconds` 秒後の時刻を持つ点を返します。
    /// - Parameters:
    ///   - sequence: セッション内の連番。
    ///   - seconds: 基準日時からの秒。
    ///   - x: 東向きの距離(m)。
    ///   - y: 北向きの距離(m)。
    /// - Returns: 点。
    static func point(_ sequence: Int64, at seconds: TimeInterval, x: Double = 0, y: Double = 0) -> DrivingRoutePoint {
        DrivingRoutePoint(
            sequence: sequence,
            coordinate: DrivingRouteTrackFixtures.coordinates.point(x: x, y: y),
            observedAt: DrivingRouteTrackFixtures.date(seconds),
            monotonicNanoseconds: UInt64((seconds + 1_000) * 1_000_000_000),
            horizontalAccuracyMeters: 5,
            altitudeMeters: nil,
            verticalAccuracyMeters: nil
        )
    }

    /// 点の列から区間を作ります。
    ///
    /// 責務: 点と精度の段階をそのまま持つ区間を返します。
    /// - Parameters:
    ///   - points: 区間の点。
    ///   - precision: 精度の段階。
    /// - Returns: 区間。
    static func segment(_ points: [DrivingRoutePoint], precision: DrivingRoutePrecision = .precise) -> DrivingRouteSegment {
        DrivingRouteSegment(points: points, precision: precision)
    }

    /// 区間の列からルートを作ります。
    ///
    /// 責務: 全点数は区間の点数の和、除外数は 0 としてルートを返します。
    /// - Parameter segments: 区間。
    /// - Returns: ルート。
    static func route(_ segments: [DrivingRouteSegment]) -> DrivingRoute {
        DrivingRoute(segments: segments, totalFixCount: segments.reduce(0) { $0 + $1.points.count }, excludedFixCount: 0)
    }
}
