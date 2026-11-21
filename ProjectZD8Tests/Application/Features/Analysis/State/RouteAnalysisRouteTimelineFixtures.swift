import Foundation
@testable import ProjectZD8

/// 走行ルートの色分け・強調・地図の層・連動のテストで、メートル単位の形と秒から時間の軸を組み立てる補助です。
///
/// 座標は `GeoTestCoordinates`(製品の座標計算に頼らない式)で作り、時刻は `RouteAnalysisTimelinePointFixtures.base` からの秒です。
enum RouteAnalysisRouteTimelineFixtures {
    /// メートル単位の座標を作る補助です(原点は既定)。
    static let coordinates = GeoTestCoordinates()
    /// 時刻の基準です。
    static let base = RouteAnalysisTimelinePointFixtures.base

    /// 基準から `seconds` 秒後の日時を返します。
    ///
    /// 責務: テストの時刻を基準からの秒で表せるようにします。
    /// - Parameter seconds: 基準からの秒。
    /// - Returns: 日時。
    static func date(_ seconds: TimeInterval) -> Date {
        base.addingTimeInterval(seconds)
    }

    /// 時間の軸の1点を作ります。
    ///
    /// 責務: 指定の位置の番号・連番・区間・精度・座標(東へ x m、北へ y m)・時刻・標高を持つ点を返します。
    /// - Parameters:
    ///   - index: 点の位置の番号。
    ///   - sequence: 位置の連番。
    ///   - segmentIndex: 区間の番号。
    ///   - x: 東向きの距離(m)。
    ///   - y: 北向きの距離(m)。
    ///   - seconds: 基準からの秒。
    ///   - precision: 精度の段階。
    ///   - altitude: 標高(m)。
    /// - Returns: 点。
    static func point(
        index: Int,
        sequence: Int64,
        segmentIndex: Int,
        x: Double,
        y: Double = 0,
        seconds: TimeInterval,
        precision: DrivingRoutePrecision = .precise,
        altitude: Double? = nil
    ) -> RouteAnalysisTimelinePoint {
        RouteAnalysisTimelinePoint(
            index: index,
            sequence: sequence,
            segmentIndex: segmentIndex,
            precision: precision,
            coordinate: coordinates.point(x: x, y: y),
            date: date(seconds),
            altitudeMeters: altitude
        )
    }

    /// 区間ごとの東向きの位置の列から時間の軸を作ります。
    ///
    /// 責務: 点を通し番号で並べ、連番と時刻(秒)を通し番号と同じにし、区間の番号と精度を区間ごとに付けます。
    /// - Parameters:
    ///   - segments: 区間ごとの東向きの距離(m)の列。
    ///   - precisions: 区間ごとの精度。足りない区間は正確です。
    /// - Returns: 実時間の時計の時間の軸。
    static func timeline(segments: [[Double]], precisions: [DrivingRoutePrecision] = []) -> RouteAnalysisTimeline {
        var points: [RouteAnalysisTimelinePoint] = []
        for (segmentIndex, xs) in segments.enumerated() {
            let precision = segmentIndex < precisions.count ? precisions[segmentIndex] : .precise
            for x in xs {
                let index = points.count
                points.append(
                    point(index: index, sequence: Int64(index), segmentIndex: segmentIndex, x: x, seconds: TimeInterval(index), precision: precision)
                )
            }
        }
        return RouteAnalysisTimeline(points: points, alignment: .wallClock)
    }

    /// 1区間のジグザグの時間の軸を作ります(間引きで点が減る形)。
    ///
    /// 責務: 東へ 100 m ずつ進み、北へ 0 m と 50 m を交互に振る点を、1秒おきに並べます。
    /// - Parameter count: 点の数。
    /// - Returns: 実時間の時計の時間の軸。
    static func zigzagTimeline(count: Int) -> RouteAnalysisTimeline {
        let points: [RouteAnalysisTimelinePoint] = (0..<count).map { index in
            point(
                index: index,
                sequence: Int64(index),
                segmentIndex: 0,
                x: Double(index) * 100,
                y: index.isMultiple(of: 2) ? 0 : 50,
                seconds: TimeInterval(index)
            )
        }
        return RouteAnalysisTimeline(points: points, alignment: .wallClock)
    }

    /// 点の列をそのまま持つ時間の軸を作ります。
    ///
    /// 責務: 与えた順の点を実時間の時計で包みます。
    /// - Parameter points: 点。
    /// - Returns: 時間の軸。
    static func timeline(points: [RouteAnalysisTimelinePoint]) -> RouteAnalysisTimeline {
        RouteAnalysisTimeline(points: points, alignment: .wallClock)
    }
}
