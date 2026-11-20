import Foundation

/// 線の規制(最高速度の区間・可変区間・一方通行・徐行)の候補が、軌跡の1点にどれだけ当てはまるかを評価します。
///
/// 候補ごとに、規制場所の全線分のうち当てはまる線分を探します。
/// - 長さが `coarseSegmentLengthMeters` 以下の線分: 距離が横方向の許容(いま乗っている候補は `exitHysteresisMeters` を足す)以内。
/// - それより長い(粗い)線分: 距離が `coarseCorridorMeters` 以内。粗くない線分が当てはまれば、そちらを優先します。
/// - 向きが分かっている時は、線分の向きとの角度差が条件を満たすこと(`Mode` を参照)。分からない時は向きで除きません。
/// 点数 = 距離 + `headingPenaltyMetersPerDegree` × 角度差 − (いま乗っている候補なら `currentRegulationBonusMeters`)。
/// 曖昧さの判定と、どの状態にするかは、結果を使う経路の側で決めます。
nonisolated struct RoadRegulationLineCandidateEvaluator: Sendable {
    /// 線分の向きの扱い方です。
    nonisolated enum Mode: Sendable {
        /// 向きを区別しない(最高速度・徐行)。線の向きとその逆向きのどちらとも比べます。
        case directionAgnostic
        /// 一方通行。通行できる向きと比べ、合えば `permitted`、逆向きなら `reverse` を出します。
        case oneWay
    }

    /// 1つの線分の当てはまり具合です。
    private struct SegmentFit {
        /// 線分の近さ。
        let proximity: GeoPolylineProximity
        /// 点数に使う角度差(度)。向きが分からなければ `nil`。
        let headingDifference: Double?
        /// 一方通行の時の進む向き。
        let travelDirection: OneWayTravelDirection?
        /// 粗い線分か。
        let isCoarse: Bool
    }

    /// しきい値です。
    private let thresholds: RoadRegulationMatchingThresholds
    /// 点と線の近さの計算器です。
    private let proximityCalculator = GeoPolylineProximityCalculator()
    /// 方位と距離の計算器です。
    private let distanceCalculator = GeoDistanceCalculator()
    /// 除外の区域の内外判定に使う計算器です。
    private let polygonCalculator = GeoPolygonCalculator()

    /// しきい値を決めて評価器を作ります。
    ///
    /// 責務: 横方向の許容・角度・点数の基準を保持します。
    /// - Parameter thresholds: しきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 線の規制の候補ごとの当てはまり具合を、点数の昇順で返します。
    ///
    /// 責務: 線の形の規制だけを評価し、当てはまらない候補を除いて、点数(同点なら行 ID)の昇順に並べます。
    /// 条件(時間・曜日・車両)では絞りません(呼び出し側で除きます)。
    /// - Parameters:
    ///   - point: 軌跡の点。
    ///   - heading: 進む向き(度)。分からなければ `nil`。
    ///   - candidates: 周辺の規制。線の形でないものは無視します。
    ///   - mode: 線分の向きの扱い方。
    ///   - currentRegulationID: いま乗っている規制。無ければ `nil`。
    /// - Returns: 当てはまる候補(点数の昇順)。
    func matches(
        point: RoadRegulationTrackPoint,
        heading: Double?,
        candidates: [RoadRegulation],
        mode: Mode,
        currentRegulationID: RoadRegulationID?
    ) -> [RoadRegulationLineMatch] {
        let validHeading = heading.flatMap { $0.isFinite ? $0 : nil }
        return candidates
            .filter { $0.kind.expectedShape == .line }
            .compactMap { regulation in
                match(regulation, point: point, heading: validHeading, mode: mode, isCurrent: regulation.id == currentRegulationID)
            }
            .sorted { ($0.score, $0.regulation.id.rawValue) < ($1.score, $1.regulation.id.rawValue) }
    }

    /// 1つの候補の当てはまり具合を求めます。
    ///
    /// 責務: 全線分の当てはまりのうち、粗くない線分の最良、無ければ粗い線分の最良を選び、点数と除外の近さを付けます。
    /// - Parameters:
    ///   - regulation: 候補の規制。
    ///   - point: 軌跡の点。
    ///   - heading: 進む向き(度)。分からなければ `nil`。
    ///   - mode: 線分の向きの扱い方。
    ///   - isCurrent: いま乗っている候補か。
    /// - Returns: 当てはまり具合。どの線分も当てはまらなければ `nil`。
    private func match(
        _ regulation: RoadRegulation,
        point: RoadRegulationTrackPoint,
        heading: Double?,
        mode: Mode,
        isCurrent: Bool
    ) -> RoadRegulationLineMatch? {
        let tolerance = lateralTolerance(for: point, isCurrent: isCurrent)
        let fits = regulation.geometry.mainParts
            .flatMap { proximityCalculator.nearestSegments(to: point.coordinate, on: $0) }
            .compactMap { fit($0, heading: heading, mode: mode, order: regulation.oneWayOrder, tolerance: tolerance) }
        let bonus = isCurrent ? thresholds.currentRegulationBonusMeters : 0
        guard let best = bestFit(fits.filter { !$0.isCoarse }) ?? bestFit(fits) else { return nil }
        return RoadRegulationLineMatch(
            regulation: regulation,
            distanceMeters: best.proximity.distanceMeters,
            headingDifference: best.headingDifference,
            travelDirection: best.travelDirection,
            score: rawScore(best) - bonus,
            isCoarse: best.isCoarse,
            isNearExclusion: isNearExclusion(point.coordinate, parts: regulation.geometry.exclusionParts, tolerance: tolerance)
        )
    }

    /// 点に対する横方向の許容を返します。
    ///
    /// 責務: 精度から許容を求め、いま乗っている候補なら残す幅を足します。
    /// - Parameters:
    ///   - point: 軌跡の点。
    ///   - isCurrent: いま乗っている候補か。
    /// - Returns: 横方向の許容(m)。
    private func lateralTolerance(for point: RoadRegulationTrackPoint, isCurrent: Bool) -> Double {
        let base = thresholds.lateralTolerance(accuracy: point.horizontalAccuracyMeters)
        return isCurrent ? base + thresholds.exitHysteresisMeters : base
    }

    /// 1つの線分が当てはまるかを調べます。
    ///
    /// 責務: 線分の粗さに応じた距離の上限と、向きの条件を確かめます。
    /// - Parameters:
    ///   - proximity: 線分の近さ。
    ///   - heading: 進む向き(度)。分からなければ `nil`。
    ///   - mode: 線分の向きの扱い方。
    ///   - order: 一方通行の座標の並び方。
    ///   - tolerance: 粗くない線分の距離の上限(m)。
    /// - Returns: 当てはまり具合。当てはまらなければ `nil`。
    private func fit(
        _ proximity: GeoPolylineProximity,
        heading: Double?,
        mode: Mode,
        order: RoadRegulationOneWayOrder?,
        tolerance: Double
    ) -> SegmentFit? {
        let isCoarse = proximity.segmentLengthMeters > thresholds.coarseSegmentLengthMeters
        guard proximity.distanceMeters <= (isCoarse ? thresholds.coarseCorridorMeters : tolerance) else { return nil }
        guard let heading else {
            return SegmentFit(proximity: proximity, headingDifference: nil, travelDirection: nil, isCoarse: isCoarse)
        }
        let bearing = proximity.segmentBearingDegrees
        let orientation = mode == .oneWay
            ? oneWayOrientation(heading: heading, segmentBearing: bearing, order: order)
            : agnosticOrientation(heading: heading, segmentBearing: bearing)
        guard let orientation else { return nil }
        return SegmentFit(
            proximity: proximity,
            headingDifference: orientation.difference,
            travelDirection: orientation.direction,
            isCoarse: isCoarse
        )
    }

    /// 向きを区別しない時の角度差を返します。
    ///
    /// 責務: min(角度差(向き, 線分の方位), 角度差(向き, 線分の方位 + 180)) を求め、
    /// `headingAlignmentDegrees` 以下の時だけ返します。
    /// - Parameters:
    ///   - heading: 進む向き(度)。
    ///   - segmentBearing: 線分の方位(度)。
    /// - Returns: 0...90 の角度差と、進む向き(常に `nil`)。向きが合わなければ `nil`。
    private func agnosticOrientation(
        heading: Double,
        segmentBearing: Double
    ) -> (difference: Double, direction: OneWayTravelDirection?)? {
        let difference = min(
            distanceCalculator.angularDifference(heading, segmentBearing),
            distanceCalculator.angularDifference(heading, segmentBearing + 180)
        )
        return difference <= thresholds.headingAlignmentDegrees ? (difference, nil) : nil
    }

    /// 一方通行の時の進む向きと、点数に使う角度差を返します。
    ///
    /// 責務: 通行できる向き p(並びが `.permittedDirection` なら線分の方位、そうでなければその逆)との角度差が
    /// `headingAlignmentDegrees` 以下なら `permitted`、`reverseHeadingDegrees` 以上なら `reverse` とします。
    /// 点数に使う角度差は、`permitted` なら p との差、`reverse` なら p の逆向きとの差です。
    /// - Parameters:
    ///   - heading: 進む向き(度)。
    ///   - segmentBearing: 線分の方位(度)。
    ///   - order: 一方通行の座標の並び方。
    /// - Returns: 角度差と進む向き。その間の角度なら `nil`。
    private func oneWayOrientation(
        heading: Double,
        segmentBearing: Double,
        order: RoadRegulationOneWayOrder?
    ) -> (difference: Double, direction: OneWayTravelDirection?)? {
        let permittedBearing = order == .permittedDirection ? segmentBearing : segmentBearing + 180
        let difference = distanceCalculator.angularDifference(heading, permittedBearing)
        if difference <= thresholds.headingAlignmentDegrees { return (difference, .permitted) }
        if difference >= thresholds.reverseHeadingDegrees { return (180 - difference, .reverse) }
        return nil
    }

    /// 当てはまりのうち点数が最も小さいものを返します。
    ///
    /// 責務: 点数(ボーナスを除く)が同じなら先に現れた線分を選びます。
    /// - Parameter fits: 当てはまりの一覧。
    /// - Returns: 最良の当てはまり。空なら `nil`。
    private func bestFit(_ fits: [SegmentFit]) -> SegmentFit? {
        fits.min { rawScore($0) < rawScore($1) }
    }

    /// いま乗っている候補のボーナスを除いた点数を返します。
    ///
    /// 責務: 距離 + 角度差1度あたりの不利 × 角度差 を求めます(向きが分からなければ距離だけ)。
    /// - Parameter fit: 当てはまり。
    /// - Returns: 点数(m)。
    private func rawScore(_ fit: SegmentFit) -> Double {
        fit.proximity.distanceMeters + thresholds.headingPenaltyMetersPerDegree * (fit.headingDifference ?? 0)
    }

    /// 除外の形状が横方向の許容内にあるかを返します。
    ///
    /// 責務: 除外の区間ごとに、1点なら点までの距離、2点以上なら線までの距離を許容と比べ、閉じた輪なら内側かも確かめます。
    /// - Parameters:
    ///   - coordinate: 軌跡の点の位置。
    ///   - parts: 除外の区間ごとの点の列。
    ///   - tolerance: 横方向の許容(m)。
    /// - Returns: どれかの除外の形状が許容内にあれば `true`。
    private func isNearExclusion(_ coordinate: GeoCoordinate, parts: [[GeoCoordinate]], tolerance: Double) -> Bool {
        parts.contains { part in
            if isClosedRing(part), polygonCalculator.contains(coordinate, ring: part) { return true }
            guard let distance = distanceToPart(coordinate, part: part) else { return false }
            return distance <= tolerance
        }
    }

    /// 除外の区間までの距離を返します。
    ///
    /// 責務: 1点なら点までの距離、2点以上なら線までの最短距離を求めます。
    /// - Parameters:
    ///   - coordinate: 軌跡の点の位置。
    ///   - part: 除外の区間の点の列。
    /// - Returns: 距離(m)。点が無い・長さのある線分が無ければ点までの距離か `nil`。
    private func distanceToPart(_ coordinate: GeoCoordinate, part: [GeoCoordinate]) -> Double? {
        if let distance = proximityCalculator.nearest(to: coordinate, on: part)?.distanceMeters { return distance }
        return part.first.map { distanceCalculator.distanceMeters(coordinate, $0) }
    }

    /// 点の列が閉じた輪(面)かを返します。
    ///
    /// 責務: 4点以上で最初と最後が同じ点かを確かめます。
    /// - Parameter part: 点の列。
    /// - Returns: 閉じた輪なら `true`。
    private func isClosedRing(_ part: [GeoCoordinate]) -> Bool {
        part.count >= 4 && part.first == part.last
    }
}
