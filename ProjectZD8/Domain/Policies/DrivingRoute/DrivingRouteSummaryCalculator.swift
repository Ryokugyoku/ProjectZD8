import Foundation

/// 走行ルートの長さ・記録できた時間・記録できた割合を求めます。
nonisolated struct DrivingRouteSummaryCalculator: Sendable {
    /// 点間の距離の計算器。
    private let distance: GeoDistanceCalculator

    /// 距離の計算器から作ります。
    ///
    /// 責務: 長さの計算に使う距離の計算器を保持します。
    /// - Parameter distance: 点間の距離の計算器。
    init(distance: GeoDistanceCalculator = .init()) {
        self.distance = distance
    }

    /// 走行ルートの要約を返します。
    ///
    /// 責務: 区間内だけの長さと記録時間を合計し、セッションの時間に対する割合を 0...1 に切り詰めて求めます。
    /// 割合の分母は `(終了 ?? 最後の点の時刻 ?? 開始) − 開始` で、0以下なら割合は `nil` です。
    /// - Parameters:
    ///   - route: 区切った走行ルート。
    ///   - sessionStartedAt: セッションの開始時刻。
    ///   - sessionEndedAt: セッションの終了時刻。進行中なら `nil`。
    /// - Returns: 要約。
    func summary(of route: DrivingRoute, sessionStartedAt: Date, sessionEndedAt: Date?) -> DrivingRouteSummary {
        let recordedDuration = route.segments.reduce(0) { $0 + Self.duration(of: $1) }
        let sessionEnd = sessionEndedAt ?? route.lastPoint?.observedAt ?? sessionStartedAt
        let sessionDuration = sessionEnd.timeIntervalSince(sessionStartedAt)
        return DrivingRouteSummary(
            lengthMeters: route.segments.reduce(0) { $0 + length(of: $1) },
            recordedDuration: recordedDuration,
            coverageRatio: Self.coverageRatio(recorded: recordedDuration, session: sessionDuration)
        )
    }

    /// 区間の長さを返します。
    ///
    /// 責務: 区間内の隣り合う点の距離を合計します(1点の区間は0)。
    /// - Parameter segment: 区間。
    /// - Returns: 長さ(m)。
    private func length(of segment: DrivingRouteSegment) -> Double {
        zip(segment.points, segment.points.dropFirst()).reduce(0) { total, pair in
            total + distance.distanceMeters(pair.0.coordinate, pair.1.coordinate)
        }
    }

    /// 区間の記録時間を返します。
    ///
    /// 責務: 区間の最後の点と最初の点の時刻の差を求めます(点が無ければ0)。
    /// - Parameter segment: 区間。
    /// - Returns: 記録時間(秒)。
    private static func duration(of segment: DrivingRouteSegment) -> TimeInterval {
        guard let first = segment.points.first, let last = segment.points.last else { return 0 }
        return last.observedAt.timeIntervalSince(first.observedAt)
    }

    /// 記録できた割合を返します。
    ///
    /// 責務: 記録時間 ÷ セッションの時間を 0...1 に切り詰めます。分母が0以下(または有限でない)なら `nil` を返します。
    /// - Parameters:
    ///   - recorded: 記録時間(秒)。
    ///   - session: セッションの時間(秒)。
    /// - Returns: 割合。
    private static func coverageRatio(recorded: TimeInterval, session: TimeInterval) -> Double? {
        guard session > 0, session.isFinite else { return nil }
        return min(max(recorded / session, 0), 1)
    }
}
