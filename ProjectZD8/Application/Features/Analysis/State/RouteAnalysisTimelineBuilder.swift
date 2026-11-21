import Foundation

/// 区切った走行ルートを、解析の時間の軸(時刻を揃えた点の列)にします。
///
/// 垂直精度の悪い点・垂直精度の無い点の標高は使いません(海抜の目安として出すため)。
nonisolated struct RouteAnalysisTimelineBuilder: Sendable {
    /// 標高を使える垂直精度の上限(m、ちょうどを含む)です。
    private let maximumVerticalAccuracyMeters: Double

    /// 標高を使う垂直精度の上限を固定して生成します。
    ///
    /// 責務: 標高の採否に使う上限を保持します。
    /// - Parameter maximumVerticalAccuracyMeters: 標高を使える垂直精度の上限(m)。既定は 15。
    init(maximumVerticalAccuracyMeters: Double = 15) {
        self.maximumVerticalAccuracyMeters = maximumVerticalAccuracyMeters
    }

    /// 走行ルートの点の時刻の組を返します。
    ///
    /// 責務: 全区間の点を順に、実時間と単調時刻の組へ写します(時計の選び方の判定に使います)。
    /// - Parameter route: 区切った走行ルート。
    /// - Returns: 点の順の時刻の組。
    func clockStamps(of route: DrivingRoute) -> [TelemetryClockStamp] {
        route.points.map { TelemetryClockStamp(observedAt: $0.observedAt, monotonicNanoseconds: $0.monotonicNanoseconds) }
    }

    /// 走行ルートを、時刻を揃えた時間の軸にします。
    ///
    /// 責務: 各点に通し番号・区間の番号・精度の段階・揃えた時刻・使える標高を付け、`date` の昇順に安定に並べます。
    /// - Parameters:
    ///   - route: 区切った走行ルート。
    ///   - alignment: 時計の選び方。
    /// - Returns: 時間の軸。
    func timeline(route: DrivingRoute, alignment: TelemetryTimeAlignment) -> RouteAnalysisTimeline {
        var points: [RouteAnalysisTimelinePoint] = []
        for (segmentIndex, segment) in route.segments.enumerated() {
            for point in segment.points {
                points.append(timelinePoint(point, index: points.count, segmentIndex: segmentIndex, precision: segment.precision, alignment: alignment))
            }
        }
        return RouteAnalysisTimeline(points: Self.stablySortedByDate(points), alignment: alignment)
    }

    /// 走行ルートの1点を時間の軸の点にします。
    ///
    /// 責務: 時計の選び方で時刻を揃え、標高を採否の規則で絞ります。
    /// - Parameters:
    ///   - point: 走行ルートの点。
    ///   - index: 走行ルートの点の列での位置。
    ///   - segmentIndex: 点が属する区間の番号。
    ///   - precision: 区間の精度の段階。
    ///   - alignment: 時計の選び方。
    /// - Returns: 時間の軸の点。
    private func timelinePoint(
        _ point: DrivingRoutePoint,
        index: Int,
        segmentIndex: Int,
        precision: DrivingRoutePrecision,
        alignment: TelemetryTimeAlignment
    ) -> RouteAnalysisTimelinePoint {
        let stamp = TelemetryClockStamp(observedAt: point.observedAt, monotonicNanoseconds: point.monotonicNanoseconds)
        return RouteAnalysisTimelinePoint(
            index: index,
            sequence: point.sequence,
            segmentIndex: segmentIndex,
            precision: precision,
            coordinate: point.coordinate,
            date: alignment.date(for: stamp),
            altitudeMeters: usableAltitude(of: point)
        )
    }

    /// 点の標高を、使える時だけ返します。
    ///
    /// 責務: 標高が有限で、垂直精度が 0 以上かつ上限以内の時だけ標高を返します(負の垂直精度は無効とみなします)。
    /// - Parameter point: 走行ルートの点。
    /// - Returns: 使える標高。使えない時は `nil`。
    private func usableAltitude(of point: DrivingRoutePoint) -> Double? {
        guard let altitude = point.altitudeMeters, altitude.isFinite,
              let accuracy = point.verticalAccuracyMeters, accuracy >= 0, accuracy <= maximumVerticalAccuracyMeters
        else {
            return nil
        }
        return altitude
    }

    /// 点を `date` の昇順に安定に並べます。
    ///
    /// 責務: 同じ時刻の点は元の順(通し番号の順)を保って並べます。
    /// - Parameter points: 元の順の点。
    /// - Returns: 並べた点。
    private static func stablySortedByDate(_ points: [RouteAnalysisTimelinePoint]) -> [RouteAnalysisTimelinePoint] {
        points.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date < rhs.date : lhs.index < rhs.index
        }
    }
}
