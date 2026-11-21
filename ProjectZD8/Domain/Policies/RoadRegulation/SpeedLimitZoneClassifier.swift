import Foundation

/// 最高速度の区域(114。ゾーン30など)に対して、軌跡の1点の状態を決めます。
///
/// 条件が `doesNotApply` の区域は除き、次の順に決めます。
/// 1. どれかの区域の境界まで `zoneBoundaryMarginMeters` 未満(内側でも外側でも) → `nearZoneBoundary`。
/// 2. 内側にある区域が無い → `nil`(区域では決まらない)。
/// 3. 内側にある区域の制限値が違う → `ambiguousCandidates`。
/// 4. 条件が当てはまる区域があればその区域(行 ID の最小)、無ければ条件が不明 → `conditionUnknown`。
/// 5. その区域の除外の形状が横方向の許容内 → `nearExclusionArea`。
/// 6. それ以外 → `regulated`。
nonisolated struct SpeedLimitZoneClassifier: Sendable {
    /// 内側にある区域と、その条件の判定です。
    private struct InsideZone {
        /// 区域の規制。
        let regulation: RoadRegulation
        /// 条件の判定(`applies` または `unknown`)。
        let applicability: RegulationApplicability
    }

    /// しきい値です。
    private let thresholds: RoadRegulationMatchingThresholds
    /// 多角形の計算器です。
    private let polygonCalculator = GeoPolygonCalculator()
    /// 点と線の近さの計算器です。
    private let proximityCalculator = GeoPolylineProximityCalculator()
    /// 距離の計算器です。
    private let distanceCalculator = GeoDistanceCalculator()

    /// しきい値を決めて分類器を作ります。
    ///
    /// 責務: 境目の幅と横方向の許容の基準を保持します。
    /// - Parameter thresholds: しきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 区域に対する点の状態を返します。
    ///
    /// 責務: 区域を行 ID の昇順に並べてから、境目の近さ・内外・制限値の重なり・条件・除外の順に調べます(入力の順に依存しません)。
    /// - Parameters:
    ///   - point: 軌跡の点。
    ///   - candidates: 周辺の規制(区域でないものは無視します)。
    ///   - applicability: 規制の条件がその時刻に当てはまるかを返す関数。
    /// - Returns: 区域で決まった状態。どの区域の内側でもなく境目からも遠ければ `nil`。
    func status(
        point: RoadRegulationTrackPoint,
        candidates: [RoadRegulation],
        applicability: (RoadRegulation, Date) -> RegulationApplicability
    ) -> SpeedLimitStatus? {
        let zones = candidates.sorted { $0.id < $1.id }.compactMap { regulation -> InsideZone? in
            guard regulation.kind == .speedLimitZone else { return nil }
            let value = applicability(regulation, point.observedAt)
            return value == .doesNotApply ? nil : InsideZone(regulation: regulation, applicability: value)
        }
        if let near = zones.first(where: { isNearBoundary(point.coordinate, of: $0.regulation) }) {
            return .undeterminable(.nearZoneBoundary, near.regulation.id)
        }
        let inside = zones.filter { isInside(point.coordinate, of: $0.regulation) }
        guard let first = inside.first else { return nil }
        guard Set(inside.map { $0.regulation.speedLimitKph }).count == 1 else {
            return .undeterminable(.ambiguousCandidates, nil)
        }
        let chosen = inside.first { $0.applicability == .applies } ?? first
        return status(of: chosen, at: point)
    }

    /// 内側にある1つの区域の状態を返します。
    ///
    /// 責務: 条件の不明・除外の近さ・制限値の欠けを確かめ、それ以外は規制に乗っているとします。
    /// - Parameters:
    ///   - zone: 選んだ区域。
    ///   - point: 軌跡の点。
    /// - Returns: 状態。
    private func status(of zone: InsideZone, at point: RoadRegulationTrackPoint) -> SpeedLimitStatus {
        let id = zone.regulation.id
        if zone.applicability != .applies { return .undeterminable(.conditionUnknown, id) }
        if isNearExclusion(point, of: zone.regulation) { return .undeterminable(.nearExclusionArea, id) }
        guard let limit = zone.regulation.speedLimitKph else { return .undeterminable(.variableSpeedLimit, id) }
        return .regulated(id, limitKph: limit)
    }

    /// 点が区域の境界の近くにあるかを返します。
    ///
    /// 責務: 区域の輪ごとの境界までの距離の最小値を、境目の幅と比べます。
    /// - Parameters:
    ///   - coordinate: 点の位置。
    ///   - zone: 区域の規制。
    /// - Returns: 境界まで幅未満なら `true`。
    private func isNearBoundary(_ coordinate: GeoCoordinate, of zone: RoadRegulation) -> Bool {
        zone.geometry.mainParts.contains { ring in
            guard let distance = polygonCalculator.distanceToBoundaryMeters(coordinate, ring: ring) else { return false }
            return distance < thresholds.zoneBoundaryMarginMeters
        }
    }

    /// 点が区域の内側にあるかを返します。
    ///
    /// 責務: 区域のどれかの輪の内側にあるかを調べます。
    /// - Parameters:
    ///   - coordinate: 点の位置。
    ///   - zone: 区域の規制。
    /// - Returns: 内側なら `true`。
    private func isInside(_ coordinate: GeoCoordinate, of zone: RoadRegulation) -> Bool {
        zone.geometry.mainParts.contains { polygonCalculator.contains(coordinate, ring: $0) }
    }

    /// 区域の除外の形状が横方向の許容内にあるかを返します。
    ///
    /// 責務: 除外の区間ごとに、閉じた輪の内側か、点・線までの距離が許容以内かを調べます。
    /// - Parameters:
    ///   - point: 軌跡の点。
    ///   - zone: 区域の規制。
    /// - Returns: 除外の形状が許容内にあれば `true`。
    private func isNearExclusion(_ point: RoadRegulationTrackPoint, of zone: RoadRegulation) -> Bool {
        let tolerance = thresholds.lateralTolerance(accuracy: point.horizontalAccuracyMeters)
        return zone.geometry.exclusionParts.contains { part in
            if part.count >= 4, part.first == part.last, polygonCalculator.contains(point.coordinate, ring: part) { return true }
            guard let distance = distance(from: point.coordinate, to: part) else { return false }
            return distance <= tolerance
        }
    }

    /// 除外の区間までの距離を返します。
    ///
    /// 責務: 線として近さを求め、長さのある線分が無ければ最初の点までの距離を返します。
    /// - Parameters:
    ///   - coordinate: 点の位置。
    ///   - part: 除外の区間の点の列。
    /// - Returns: 距離(m)。点が無ければ `nil`。
    private func distance(from coordinate: GeoCoordinate, to part: [GeoCoordinate]) -> Double? {
        if let distance = proximityCalculator.nearest(to: coordinate, on: part)?.distanceMeters { return distance }
        return part.first.map { distanceCalculator.distanceMeters(coordinate, $0) }
    }
}
