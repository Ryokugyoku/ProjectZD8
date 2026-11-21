import Foundation

/// 一方通行の経路で、軌跡の1点で観測した状態を決めます(確定は呼び出し側の `RoadRegulationStatusConfirmation`)。
///
/// 候補は一方通行(11)で、条件が `doesNotApply` のものは除きます。
/// - 向きが分かる時: 通行できる向きとの角度差が `headingAlignmentDegrees` 以下 → `on(id, .permitted)`、
///   `reverseHeadingDegrees` 以上 → `on(id, .reverse)`、その間は候補にしません。
/// - 向きが分からず横方向の許容内に候補がある → `undeterminable(.headingUnknown, id)`。
/// - 曖昧(点数の近い候補の進む向きか条件の判定が違う)→ `ambiguousCandidates`。条件が不明 → `conditionUnknown`。
///   除外の近く → `nearExclusionArea`。粗い線分の近く → `coarseGeometry`。
/// - どれにも当たらない(範囲の外を含む)→ `none`。
nonisolated struct OneWayChannelTracker: Sendable {
    /// 線の候補の絞り込み器です。
    private let resolver: RoadRegulationLineChannelResolver

    /// しきい値を決めて経路の追跡器を作ります。
    ///
    /// 責務: 線の候補の絞り込み器を用意します。
    /// - Parameter thresholds: しきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.resolver = RoadRegulationLineChannelResolver(thresholds: thresholds)
    }

    /// 1点で観測した一方通行の経路の状態を返します。
    ///
    /// 責務: 一方通行の候補を向きつきで絞り、向き・曖昧さ・条件・除外・粗さから状態を決めます。
    /// - Parameters:
    ///   - point: 軌跡の点。
    ///   - heading: 進む向き(度)。分からなければ `nil`。
    ///   - context: 周辺の規制と、範囲内かどうか。
    ///   - current: いまの確定状態(いま乗っている候補を優先するのに使う)。
    ///   - applicability: 規制の条件がその時刻に当てはまるかを返す関数。
    /// - Returns: 観測した状態。
    func observedStatus(
        point: RoadRegulationTrackPoint,
        heading: Double?,
        context: RoadRegulationCandidateContext,
        current: OneWayChannelStatus,
        applicability: (RoadRegulation, Date) -> RegulationApplicability
    ) -> OneWayChannelStatus {
        let resolution = resolver.resolve(
            point: point,
            heading: heading,
            candidates: context.regulations,
            kinds: [.oneWay],
            mode: .oneWay,
            currentRegulationID: Self.regulationID(of: current),
            applicability: applicability,
            isSameOutcome: { $0.match.travelDirection == $1.match.travelDirection && $0.applicability == $1.applicability }
        )
        switch resolution {
        case .none:
            return .none
        case .coarse(let id):
            return .undeterminable(.coarseGeometry, id)
        case .ambiguous:
            return heading == nil ? .undeterminable(.headingUnknown, nil) : .undeterminable(.ambiguousCandidates, nil)
        case .best(let candidate):
            return Self.status(of: candidate)
        }
    }

    /// 1つに絞れた候補の状態を返します。
    ///
    /// 責務: 向きの不明・条件の不明・除外の近さの順に確かめ、それ以外は進む向きつきで乗っているとします。
    /// - Parameter candidate: 絞れた候補。
    /// - Returns: 状態。
    private static func status(of candidate: RoadRegulationLineChannelResolver.Candidate) -> OneWayChannelStatus {
        let id = candidate.match.regulation.id
        guard let direction = candidate.match.travelDirection else { return .undeterminable(.headingUnknown, id) }
        if candidate.applicability != .applies { return .undeterminable(.conditionUnknown, id) }
        if candidate.match.isNearExclusion { return .undeterminable(.nearExclusionArea, id) }
        return .on(id, direction)
    }

    /// いま乗っている規制の行 ID を返します。
    ///
    /// 責務: 乗っている状態と、規制が分かっている判定できない状態から行 ID を取り出します。
    /// - Parameter status: いまの確定状態。
    /// - Returns: 行 ID。無ければ `nil`。
    private static func regulationID(of status: OneWayChannelStatus) -> RoadRegulationID? {
        switch status {
        case .on(let id, _): id
        case .undeterminable(_, let id): id
        case .pending, .none: nil
        }
    }
}
