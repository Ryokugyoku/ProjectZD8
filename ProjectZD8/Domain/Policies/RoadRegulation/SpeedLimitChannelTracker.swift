import Foundation

/// 最高速度の経路で、軌跡の1点で観測した状態を決めます(確定は呼び出し側の `RoadRegulationStatusConfirmation`)。
///
/// 上から順に評価します。
/// 1. 点がどの版の範囲にも無い → `undeterminable(.outsideRegulationData, nil)`。
/// 2. 線の候補(112 と 113。条件が `doesNotApply` のものは除く)を `RoadRegulationLineChannelResolver` で1つに絞る。
///    曖昧 → `ambiguousCandidates`。1位が 113 → `variableSpeedLimit`。条件が不明 → `conditionUnknown`。
///    片側 → `oneSidedSection`。除外の近く → `nearExclusionArea`。それ以外 → `regulated(id, L)`。
/// 3. 粗い線分の近く → `undeterminable(.coarseGeometry, id)`。
/// 4. 区域(114)を `SpeedLimitZoneClassifier` で決める。
/// 5. どれにも当たらない → `unregulated`。
nonisolated struct SpeedLimitChannelTracker: Sendable {
    /// 線の候補の絞り込み器です。
    private let resolver: RoadRegulationLineChannelResolver
    /// 区域の分類器です。
    private let zoneClassifier: SpeedLimitZoneClassifier

    /// しきい値を決めて経路の追跡器を作ります。
    ///
    /// 責務: 線の候補の絞り込み器と区域の分類器を、同じしきい値で用意します。
    /// - Parameter thresholds: しきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.resolver = RoadRegulationLineChannelResolver(thresholds: thresholds)
        self.zoneClassifier = SpeedLimitZoneClassifier(thresholds: thresholds)
    }

    /// 1点で観測した最高速度の経路の状態を返します。
    ///
    /// 責務: 範囲・線の候補・粗い線分・区域の順に調べ、どれにも当たらなければ指定なしとします。
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
        current: SpeedLimitStatus,
        applicability: (RoadRegulation, Date) -> RegulationApplicability
    ) -> SpeedLimitStatus {
        guard context.isInsideDataCoverage else { return .undeterminable(.outsideRegulationData, nil) }
        let resolution = resolver.resolve(
            point: point,
            heading: heading,
            candidates: context.regulations,
            kinds: [.speedLimitSection, .speedLimitVariableSection],
            mode: .directionAgnostic,
            currentRegulationID: Self.regulationID(of: current),
            applicability: applicability,
            isSameOutcome: Self.isSameOutcome
        )
        switch resolution {
        case .ambiguous:
            return .undeterminable(.ambiguousCandidates, nil)
        case .best(let candidate):
            return Self.status(of: candidate)
        case .coarse(let id):
            return .undeterminable(.coarseGeometry, id)
        case .none:
            return zoneClassifier.status(point: point, candidates: context.regulations, applicability: applicability) ?? .unregulated
        }
    }

    /// 1つに絞れた線の候補の状態を返します。
    ///
    /// 責務: 可変区間・条件の不明・片側・除外の近さ・制限値の欠けの順に確かめ、それ以外は規制に乗っているとします。
    /// - Parameter candidate: 絞れた候補。
    /// - Returns: 状態。
    private static func status(of candidate: RoadRegulationLineChannelResolver.Candidate) -> SpeedLimitStatus {
        let regulation = candidate.match.regulation
        let id = regulation.id
        if regulation.kind == .speedLimitVariableSection { return .undeterminable(.variableSpeedLimit, id) }
        if candidate.applicability != .applies { return .undeterminable(.conditionUnknown, id) }
        if regulation.side == .oneSide { return .undeterminable(.oneSidedSection, id) }
        if candidate.match.isNearExclusion { return .undeterminable(.nearExclusionArea, id) }
        guard let limit = regulation.speedLimitKph else { return .undeterminable(.variableSpeedLimit, id) }
        return .regulated(id, limitKph: limit)
    }

    /// 2つの候補の結果(制限値・種別・条件の判定)が同じかを返します。
    ///
    /// 責務: 曖昧さの判定に使う比べ方を決めます。
    /// - Parameters:
    ///   - lhs: 候補。
    ///   - rhs: 候補。
    /// - Returns: 同じなら `true`。
    private static func isSameOutcome(
        _ lhs: RoadRegulationLineChannelResolver.Candidate,
        _ rhs: RoadRegulationLineChannelResolver.Candidate
    ) -> Bool {
        lhs.match.regulation.speedLimitKph == rhs.match.regulation.speedLimitKph
            && lhs.match.regulation.kind == rhs.match.regulation.kind
            && lhs.applicability == rhs.applicability
    }

    /// いま乗っている規制の行 ID を返します。
    ///
    /// 責務: 規制に乗っている状態と、規制が分かっている判定できない状態から行 ID を取り出します。
    /// - Parameter status: いまの確定状態。
    /// - Returns: 行 ID。無ければ `nil`。
    private static func regulationID(of status: SpeedLimitStatus) -> RoadRegulationID? {
        switch status {
        case .regulated(let id, _): id
        case .undeterminable(_, let id): id
        case .pending, .unregulated: nil
        }
    }
}
