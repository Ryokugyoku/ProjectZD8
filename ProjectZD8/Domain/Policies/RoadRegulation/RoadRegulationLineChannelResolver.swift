import Foundation

/// 線の規制の経路(最高速度の区間・一方通行・徐行)で、軌跡の1点に当てはまる規制を1つに絞ります。
///
/// 次の順に決めます。
/// 1. 種別で候補を絞り、条件が `doesNotApply` のものを除く。
/// 2. 粗くない線分で当てはまる候補があれば、点数の最良を選ぶ。最良との点数差が `ambiguityMarginMeters` 未満の候補のうち、
///    結果(経路ごとに渡す比べ方)が最良と違うものがあれば曖昧とする。
/// 3. 粗くない候補が無く、粗い線分の近くにいれば粗い形状とする。
/// 4. どれにも当たらなければ該当なし。
/// 状態(理由)をどう決めるかは、結果を使う経路の側で決めます。
nonisolated struct RoadRegulationLineChannelResolver: Sendable {
    /// 条件の判定を添えた線の候補です。
    nonisolated struct Candidate: Equatable, Sendable {
        /// 線への当てはまり具合。
        let match: RoadRegulationLineMatch
        /// 点の時刻での条件の判定(`applies` または `unknown`)。
        let applicability: RegulationApplicability
    }

    /// 1点での絞り込みの結果です。
    nonisolated enum Resolution: Equatable, Sendable {
        /// 当てはまる候補が無い。
        case none
        /// 粗い線分の近くにいる(最も点数の良い粗い候補)。
        case coarse(RoadRegulationID)
        /// 点数の近い候補の結果が違う。
        case ambiguous
        /// 1つに絞れた。
        case best(Candidate)
    }

    /// しきい値です。
    private let thresholds: RoadRegulationMatchingThresholds
    /// 線の候補の評価器です。
    private let lineEvaluator: RoadRegulationLineCandidateEvaluator

    /// しきい値を決めて絞り込み器を作ります。
    ///
    /// 責務: 曖昧さの幅と、線の候補の評価器を保持します。
    /// - Parameter thresholds: しきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
        self.lineEvaluator = RoadRegulationLineCandidateEvaluator(thresholds: thresholds)
    }

    /// 1点で当てはまる規制を1つに絞ります。
    ///
    /// 責務: 種別と条件で候補を絞ってから線の当てはまりを評価し、曖昧さ・粗さ・該当なしを見分けます。
    /// - Parameters:
    ///   - point: 軌跡の点。
    ///   - heading: 進む向き(度)。分からなければ `nil`。
    ///   - candidates: 周辺の規制。
    ///   - kinds: この経路で使う種別。
    ///   - mode: 線分の向きの扱い方。
    ///   - currentRegulationID: いま乗っている規制。無ければ `nil`。
    ///   - applicability: 規制の条件がその時刻に当てはまるかを返す関数。
    ///   - isSameOutcome: 2つの候補の結果が同じかを返す関数(曖昧さの判定に使う)。
    /// - Returns: 絞り込みの結果。
    func resolve(
        point: RoadRegulationTrackPoint,
        heading: Double?,
        candidates: [RoadRegulation],
        kinds: Set<RoadRegulationKind>,
        mode: RoadRegulationLineCandidateEvaluator.Mode,
        currentRegulationID: RoadRegulationID?,
        applicability: (RoadRegulation, Date) -> RegulationApplicability,
        isSameOutcome: (Candidate, Candidate) -> Bool
    ) -> Resolution {
        var applicabilities: [RoadRegulationID: RegulationApplicability] = [:]
        let usable = candidates.filter { regulation in
            guard kinds.contains(regulation.kind) else { return false }
            let value = applicability(regulation, point.observedAt)
            applicabilities[regulation.id] = value
            return value != .doesNotApply
        }
        let matches = lineEvaluator.matches(
            point: point,
            heading: heading,
            candidates: usable,
            mode: mode,
            currentRegulationID: currentRegulationID
        )
        let fine = matches.filter { !$0.isCoarse }.map { match in
            Candidate(match: match, applicability: applicabilities[match.regulation.id] ?? .unknown)
        }
        if let best = fine.first {
            return isAmbiguous(best, among: fine, isSameOutcome: isSameOutcome) ? .ambiguous : .best(best)
        }
        if let coarse = matches.first(where: \.isCoarse) {
            return .coarse(coarse.regulation.id)
        }
        return .none
    }

    /// 最良の候補が曖昧かを返します。
    ///
    /// 責務: 最良との点数差が幅未満の候補のうち、結果が最良と違うものがあるかを調べます。
    /// - Parameters:
    ///   - best: 最良の候補。
    ///   - candidates: 点数の昇順の候補(最良を含む)。
    ///   - isSameOutcome: 2つの候補の結果が同じかを返す関数。
    /// - Returns: 曖昧なら `true`。
    private func isAmbiguous(
        _ best: Candidate,
        among candidates: [Candidate],
        isSameOutcome: (Candidate, Candidate) -> Bool
    ) -> Bool {
        candidates.dropFirst().contains { other in
            other.match.score - best.match.score < thresholds.ambiguityMarginMeters && !isSameOutcome(best, other)
        }
    }
}
