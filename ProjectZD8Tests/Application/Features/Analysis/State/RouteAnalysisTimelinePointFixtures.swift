import Foundation
@testable import ProjectZD8

/// 時間の軸(`RouteAnalysisTimeline`)のテストで、指定の時刻の点を作る補助です。
enum RouteAnalysisTimelinePointFixtures {
    /// 基準の日時です。
    static let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// 基準から `seconds` 秒後の点を作ります。
    ///
    /// 責務: 位置と標高は固定で、番号と時刻だけが異なる点を返します。
    /// - Parameters:
    ///   - index: 点の位置の番号(区別のために使います)。
    ///   - seconds: 基準からの秒。
    /// - Returns: 時間の軸の点。
    static func point(_ index: Int, at seconds: TimeInterval) -> RouteAnalysisTimelinePoint {
        guard let coordinate = GeoCoordinate(latitude: 35, longitude: 139) else {
            preconditionFailure("テストの座標が範囲外です")
        }
        return RouteAnalysisTimelinePoint(
            index: index,
            sequence: Int64(index),
            segmentIndex: 0,
            precision: .precise,
            coordinate: coordinate,
            date: base.addingTimeInterval(seconds),
            altitudeMeters: nil
        )
    }

    /// 秒の列から時間の軸を作ります。
    ///
    /// 責務: 与えられた順(昇順の前提)に点を並べ、実時間の時計で包みます。
    /// - Parameter seconds: 基準からの秒の列。
    /// - Returns: 時間の軸。
    static func timeline(_ seconds: [TimeInterval]) -> RouteAnalysisTimeline {
        RouteAnalysisTimeline(points: seconds.enumerated().map { point($0.offset, at: $0.element) }, alignment: .wallClock)
    }
}
