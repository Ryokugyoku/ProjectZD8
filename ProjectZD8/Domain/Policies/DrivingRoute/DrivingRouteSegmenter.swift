import Foundation

/// 1セッションの軌跡を、精度で点を除いたうえで、途切れ・事象・精度段階の切替・位置の飛びで区間に分けます。
///
/// - 点ごとの精度の段階は、その点の時刻以前(同時刻を含む)で最後の取得事象(`recording` / `recordingWithReducedAccuracy`)で決めます。
///   それより前の点は最初の取得事象に従い、取得事象が無ければ正確とします。事象は時刻の順(同時刻は ordinal の順)に並べ直して使います。
/// - 精度で除いた点は、それ自体では線を切りません。残った前後の点で判定をやり直します。
/// - 隣り合う2点は、精度の段階が同じ、時間差が正でしきい値以下、推定の速さが上限以下、
///   `前の点の時刻 < 事象の時刻 ≤ 次の点の時刻` に記録中以外の事象が無い、をすべて満たす時だけつなぎます。
nonisolated struct DrivingRouteSegmenter: Sendable {
    /// 精度の段階が切り替わった時刻と、切り替え後の段階です。
    private struct PrecisionChange: Sendable {
        /// 事象の時刻。
        let occurredAt: Date
        /// 事象の後の精度の段階。
        let precision: DrivingRoutePrecision
    }

    /// 区切りのしきい値。
    private let thresholds: DrivingRouteSegmentationThresholds
    /// 推定の速さに使う距離の計算器。
    private let distance: GeoDistanceCalculator

    /// しきい値と距離の計算器から作ります。
    ///
    /// 責務: 区切りの判定に使うしきい値と距離の計算器を保持します。
    /// - Parameters:
    ///   - thresholds: 区切りのしきい値。既定は `.standard`。
    ///   - distance: 点間の距離の計算器。
    init(thresholds: DrivingRouteSegmentationThresholds = .standard, distance: GeoDistanceCalculator = .init()) {
        self.thresholds = thresholds
        self.distance = distance
    }

    /// 軌跡を区間に分けた走行ルートを返します。
    ///
    /// 責務: 精度で点を除き、時間差・事象・精度段階の切替・位置の飛びで区間に分けます。
    /// - Parameter track: 位置のサンプル(sequence 昇順)と事象(ordinal 昇順)。
    /// - Returns: 区間の列と、全サンプル数・除いたサンプル数。
    func route(from track: ConnectionSessionLocationTrack) -> DrivingRoute {
        let changes = Self.precisionChanges(in: track.events)
        let interruptions = Self.interruptionDates(in: track.events)
        var segments: [DrivingRouteSegment] = []
        var current: [DrivingRoutePoint] = []
        var currentPrecision = DrivingRoutePrecision.precise
        var excludedCount = 0
        for sample in track.samples {
            let precision = Self.precision(at: sample.fix.observedAt, changes: changes)
            guard let point = acceptedPoint(sample, precision: precision) else {
                excludedCount += 1
                continue
            }
            if let previous = current.last,
               !connects(previous, point, precisions: (currentPrecision, precision), interruptions: interruptions) {
                segments.append(DrivingRouteSegment(points: current, precision: currentPrecision))
                current = []
            }
            if current.isEmpty { currentPrecision = precision }
            current.append(point)
        }
        if !current.isEmpty {
            segments.append(DrivingRouteSegment(points: current, precision: currentPrecision))
        }
        return DrivingRoute(segments: segments, totalFixCount: track.samples.count, excludedFixCount: excludedCount)
    }

    /// サンプルを、精度の検査を通った点に直します。
    ///
    /// 責務: 座標が有効で、水平精度がその段階の上限以下(ちょうどは残す)のサンプルだけを点にします。
    /// - Parameters:
    ///   - sample: 位置のサンプル。
    ///   - precision: その点の精度の段階。
    /// - Returns: 除く点なら `nil`。
    private func acceptedPoint(_ sample: ConnectionSessionLocationSample, precision: DrivingRoutePrecision) -> DrivingRoutePoint? {
        let fix = sample.fix
        guard fix.horizontalAccuracyMeters <= maximumHorizontalAccuracy(for: precision),
              let coordinate = GeoCoordinate(latitude: fix.latitude, longitude: fix.longitude)
        else { return nil }
        return DrivingRoutePoint(
            sequence: sample.sequence,
            coordinate: coordinate,
            observedAt: fix.observedAt,
            monotonicNanoseconds: fix.monotonicNanoseconds,
            horizontalAccuracyMeters: fix.horizontalAccuracyMeters,
            altitudeMeters: fix.altitudeMeters,
            verticalAccuracyMeters: fix.verticalAccuracyMeters
        )
    }

    /// 隣り合う2点を1本の線でつなぐかを返します。
    ///
    /// 責務: 精度の段階・時間差・推定の速さ・間の事象のすべてが条件を満たす時だけ `true` を返します。
    /// - Parameters:
    ///   - previous: 区間の最後の点。
    ///   - next: 次に残った点。
    ///   - precisions: 区間の精度の段階と、次の点の精度の段階。
    ///   - interruptions: 記録中以外の事象の時刻(昇順)。
    /// - Returns: つなぐなら `true`。
    private func connects(
        _ previous: DrivingRoutePoint,
        _ next: DrivingRoutePoint,
        precisions: (current: DrivingRoutePrecision, next: DrivingRoutePrecision),
        interruptions: [Date]
    ) -> Bool {
        guard precisions.current == precisions.next else { return false }
        let elapsed = next.observedAt.timeIntervalSince(previous.observedAt)
        guard elapsed > 0, elapsed <= maximumGap(for: precisions.next) else { return false }
        let speed = distance.distanceMeters(previous.coordinate, next.coordinate) / elapsed
        guard speed <= thresholds.maximumImpliedSpeedMetersPerSecond else { return false }
        return !Self.hasInterruption(after: previous.observedAt, upTo: next.observedAt, in: interruptions)
    }

    /// 精度の段階ごとの、つなぐ最大の時間差を返します。
    ///
    /// 責務: 正確なら正確用、概略なら概略用のしきい値を選びます。
    /// - Parameter precision: 精度の段階。
    /// - Returns: 最大の時間差(秒)。
    private func maximumGap(for precision: DrivingRoutePrecision) -> TimeInterval {
        switch precision {
        case .precise: thresholds.preciseMaximumGapSeconds
        case .approximate: thresholds.approximateMaximumGapSeconds
        }
    }

    /// 精度の段階ごとの、残す最大の水平精度を返します。
    ///
    /// 責務: 正確なら正確用、概略なら概略用のしきい値を選びます。
    /// - Parameter precision: 精度の段階。
    /// - Returns: 最大の水平精度(m)。
    private func maximumHorizontalAccuracy(for precision: DrivingRoutePrecision) -> Double {
        switch precision {
        case .precise: thresholds.preciseMaximumHorizontalAccuracyMeters
        case .approximate: thresholds.approximateMaximumHorizontalAccuracyMeters
        }
    }

    /// 事象から精度の段階の切替を取り出します。
    ///
    /// 責務: 取得事象だけを、時刻の昇順(同時刻は ordinal の昇順)に並べます。
    /// - Parameter events: 位置記録の事象。
    /// - Returns: 時刻順の精度の切替。
    private static func precisionChanges(in events: [ConnectionSessionLocationEvent]) -> [PrecisionChange] {
        chronological(events).compactMap { event in
            switch event.kind {
            case .recording: PrecisionChange(occurredAt: event.occurredAt, precision: .precise)
            case .recordingWithReducedAccuracy: PrecisionChange(occurredAt: event.occurredAt, precision: .approximate)
            default: nil
            }
        }
    }

    /// 記録中以外の事象の時刻を取り出します。
    ///
    /// 責務: 取得事象以外(7種)の時刻を昇順に並べます。
    /// - Parameter events: 位置記録の事象。
    /// - Returns: 昇順の時刻。
    private static func interruptionDates(in events: [ConnectionSessionLocationEvent]) -> [Date] {
        events
            .filter { $0.kind != .recording && $0.kind != .recordingWithReducedAccuracy }
            .map(\.occurredAt)
            .sorted()
    }

    /// 事象を時刻の順に並べ直します。
    ///
    /// 責務: 時刻の昇順、同時刻は ordinal の昇順に並べます。
    /// - Parameter events: 位置記録の事象。
    /// - Returns: 並べ直した事象。
    private static func chronological(_ events: [ConnectionSessionLocationEvent]) -> [ConnectionSessionLocationEvent] {
        events.sorted { lhs, rhs in
            lhs.occurredAt != rhs.occurredAt ? lhs.occurredAt < rhs.occurredAt : lhs.ordinal < rhs.ordinal
        }
    }

    /// 点の時刻での精度の段階を返します。
    ///
    /// 責務: 時刻以前で最後の切替に従い、それより前なら最初の切替、切替が無ければ正確を返します。
    /// - Parameters:
    ///   - date: 点の時刻。
    ///   - changes: 時刻順の精度の切替。
    /// - Returns: 精度の段階。
    private static func precision(at date: Date, changes: [PrecisionChange]) -> DrivingRoutePrecision {
        let count = firstIndex(in: changes.lazy.map(\.occurredAt), after: date)
        guard count > 0 else { return changes.first?.precision ?? .precise }
        return changes[count - 1].precision
    }

    /// 2つの時刻の間(前を含まず、後を含む)に記録中以外の事象があるかを返します。
    ///
    /// 責務: `start < t ≤ end` を満たす時刻 t が昇順の列にあるかを二分探索で調べます。
    /// - Parameters:
    ///   - start: 前の点の時刻。
    ///   - end: 次の点の時刻。
    ///   - interruptions: 昇順の時刻。
    /// - Returns: あれば `true`。
    private static func hasInterruption(after start: Date, upTo end: Date, in interruptions: [Date]) -> Bool {
        let index = firstIndex(in: interruptions, after: start)
        return index < interruptions.count && interruptions[index] <= end
    }

    /// 昇順の時刻の列で、指定の時刻より後の最初の位置を返します。
    ///
    /// 責務: 二分探索で `dates[i] > date` となる最小の i(無ければ要素数)を求めます。
    /// - Parameters:
    ///   - dates: 昇順の時刻の列。
    ///   - date: 基準の時刻。
    /// - Returns: 位置(0...要素数)。
    private static func firstIndex<Dates: RandomAccessCollection>(in dates: Dates, after date: Date) -> Int
    where Dates.Element == Date, Dates.Index == Int {
        var low = dates.startIndex
        var high = dates.endIndex
        while low < high {
            let middle = low + (high - low) / 2
            if dates[middle] > date {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low - dates.startIndex
    }
}
