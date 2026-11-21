import Foundation

/// 軌跡の1点と直前の状態から、いま乗っている規制と、この点で起きた変化を求めます。
///
/// 内部に可変の状態を持たない純粋な計算です。走行後の解析(保存済みの軌跡を順に流す)と走行中で同じものを使います。
/// 1歩は次の順に進みます。
/// 1. 水平精度が `maximumUsableHorizontalAccuracyMeters` を超える(または有限でない)点は使わず、状態を変えません。
/// 2. 直前の使える点から `maximumTrackGapSeconds` を超えて空いた → `trackGap` を出し、進行中の一時停止の接近を
///    `interruptedByGap = true` で到達扱いにし、3つの経路を `pending`、向きを初期状態に戻します(経路の変化は出しません)。
/// 3. 向きを推定し、3つの経路の観測した状態を `RoadRegulationStatusConfirmation` で確定させ、切り替わった経路の変化を出します。
/// 4. 一時停止の追跡を進めます。
/// 変化の並びは、空白 → 空白での到達・打ち切り → 最高速度 → 一方通行 → 徐行 → 一時停止(到達・打ち切り、開始)です。
nonisolated struct RoadRegulationMatcher: Sendable {
    /// しきい値です。
    private let thresholds: RoadRegulationMatchingThresholds
    /// 条件の判定器です。
    private let applicabilityEvaluator: RoadRegulationApplicabilityEvaluator
    /// 向きの推定器です。
    private let headingEstimator: RoadRegulationHeadingEstimator
    /// 最高速度の経路です。
    private let speedLimitTracker: SpeedLimitChannelTracker
    /// 一方通行の経路です。
    private let oneWayTracker: OneWayChannelTracker
    /// 徐行の経路です。
    private let slowDownTracker: SlowDownChannelTracker
    /// 一時停止の追跡器です。
    private let stopTracker: StopApproachTracker

    /// しきい値と条件の判定器を決めて matcher を作ります。
    ///
    /// 責務: 向き・3つの経路・一時停止の計算器を、同じしきい値で用意します。
    /// - Parameters:
    ///   - thresholds: しきい値。
    ///   - applicability: 条件の判定器。
    init(
        thresholds: RoadRegulationMatchingThresholds = .standard,
        applicability: RoadRegulationApplicabilityEvaluator = .init()
    ) {
        self.thresholds = thresholds
        self.applicabilityEvaluator = applicability
        self.headingEstimator = RoadRegulationHeadingEstimator(thresholds: thresholds)
        self.speedLimitTracker = SpeedLimitChannelTracker(thresholds: thresholds)
        self.oneWayTracker = OneWayChannelTracker(thresholds: thresholds)
        self.slowDownTracker = SlowDownChannelTracker(thresholds: thresholds)
        self.stopTracker = StopApproachTracker(thresholds: thresholds)
    }

    /// 1点ぶん突き合わせを進めます。
    ///
    /// 責務: 使えない点を除き、空白の処理・3つの経路の確定・一時停止の追跡を行って、新しい状態と変化を返します。
    /// - Parameters:
    ///   - state: 直前の状態(最初は `.initial`)。
    ///   - point: いまの点(時刻の昇順に渡す)。
    ///   - context: この点の周辺の規制と、範囲内かどうか。
    /// - Returns: 新しい状態・いま乗っている規制・この点で起きた変化。
    func step(
        from state: RoadRegulationMatchState,
        point: RoadRegulationTrackPoint,
        context: RoadRegulationCandidateContext
    ) -> RoadRegulationMatchStep {
        guard isUsable(point) else {
            return RoadRegulationMatchStep(state: state, position: Self.position(of: state), changes: [])
        }
        let (start, gapChanges) = afterGapCheck(state, point: point)
        let mark = Self.mark(of: point)
        let heading = headingEstimator.next(start.heading, point: point)
        let applicability: (RoadRegulation, Date) -> RegulationApplicability = { [applicabilityEvaluator] regulation, date in
            applicabilityEvaluator.evaluate(regulation.conditions, at: date)
        }
        var changes = gapChanges
        let speedLimit = confirm(start.speedLimit, observed: speedLimitTracker.observedStatus(
            point: point, heading: heading.headingDegrees, context: context,
            current: start.speedLimit.current, applicability: applicability
        ), at: mark, into: &changes) { .speedLimitChanged(from: $0, to: $1, since: $2) }
        let oneWay = confirm(start.oneWay, observed: oneWayTracker.observedStatus(
            point: point, heading: heading.headingDegrees, context: context,
            current: start.oneWay.current, applicability: applicability
        ), at: mark, into: &changes) { .oneWayChanged(from: $0, to: $1, since: $2) }
        let slowDown = confirm(start.slowDown, observed: slowDownTracker.observedStatus(
            point: point, heading: heading.headingDegrees, context: context,
            current: start.slowDown.current, applicability: applicability
        ), at: mark, into: &changes) { .slowDownChanged(from: $0, to: $1, since: $2) }
        let (stops, stopChanges) = stopTracker.step(
            start.stops, point: point, heading: heading.headingDegrees,
            candidates: context.regulations, applicability: applicability
        )
        changes += stopChanges
        let next = RoadRegulationMatchState(
            heading: heading, speedLimit: speedLimit, oneWay: oneWay, slowDown: slowDown, stops: stops, lastUsableMark: mark
        )
        return RoadRegulationMatchStep(state: next, position: Self.position(of: next), changes: changes)
    }

    /// 点が突き合わせに使えるかを返します。
    ///
    /// 責務: 時刻と水平精度が有限で、水平精度が上限以下かを確かめます。
    /// - Parameter point: いまの点。
    /// - Returns: 使えるなら `true`。
    private func isUsable(_ point: RoadRegulationTrackPoint) -> Bool {
        point.time.isFinite && point.horizontalAccuracyMeters.isFinite
            && point.horizontalAccuracyMeters <= thresholds.maximumUsableHorizontalAccuracyMeters
    }

    /// 直前の使える点からの空白を調べ、空白なら状態を戻します。
    ///
    /// 責務: 空白の時は `trackGap` と一時停止の打ち切りを出し、3つの経路を `pending`、向きを初期状態に戻した状態を返します。
    /// - Parameters:
    ///   - state: 直前の状態。
    ///   - point: いまの点。
    /// - Returns: この点の処理を始める状態と、空白で出した変化。
    private func afterGapCheck(
        _ state: RoadRegulationMatchState,
        point: RoadRegulationTrackPoint
    ) -> (RoadRegulationMatchState, [RoadRegulationChange]) {
        guard let last = state.lastUsableMark, point.time - last.time > thresholds.maximumTrackGapSeconds else {
            return (state, [])
        }
        let (stops, stopChanges) = stopTracker.interruptAll(state.stops, lastUsable: last)
        let reset = RoadRegulationMatchState(
            heading: .initial,
            speedLimit: RoadRegulationStatusConfirmation(initial: .pending),
            oneWay: RoadRegulationStatusConfirmation(initial: .pending),
            slowDown: RoadRegulationStatusConfirmation(initial: .pending),
            stops: stops,
            lastUsableMark: last
        )
        return (reset, [.trackGap(lastUsable: last)] + stopChanges)
    }

    /// 観測した状態を確定待ちへ取り込み、切り替わったら変化を足します。
    ///
    /// 責務: `confirmationPoints` 点続いた時だけ切り替え、切り替えの時刻を連続の最初の点にした変化を作ります。
    /// - Parameters:
    ///   - confirmation: 直前の確定待ち。
    ///   - observed: この点で観測した状態。
    ///   - mark: この点の印。
    ///   - changes: 変化を足す先。
    ///   - makeChange: 前後の状態と時刻から変化を作る関数。
    /// - Returns: 新しい確定待ち。
    private func confirm<Status>(
        _ confirmation: RoadRegulationStatusConfirmation<Status>,
        observed: Status,
        at mark: RoadRegulationTransitionMark,
        into changes: inout [RoadRegulationChange],
        makeChange: (Status, Status, RoadRegulationTransitionMark) -> RoadRegulationChange
    ) -> RoadRegulationStatusConfirmation<Status> {
        var updated = confirmation
        if let switched = updated.observe(observed, at: mark, requiredCount: thresholds.confirmationPoints) {
            changes.append(makeChange(switched.from, switched.to, switched.since))
        }
        return updated
    }

    /// 状態からいま乗っている規制を作ります。
    ///
    /// 責務: 3つの経路の確定状態と、進行中の一時停止の接近を並べます。
    /// - Parameter state: 状態。
    /// - Returns: いま乗っている規制。
    private static func position(of state: RoadRegulationMatchState) -> RoadRegulationPosition {
        RoadRegulationPosition(
            speedLimit: state.speedLimit.current,
            oneWay: state.oneWay.current,
            slowDown: state.slowDown.current,
            activeStopApproaches: state.stops.activeApproachKeys
        )
    }

    /// 点の印を作ります。
    ///
    /// 責務: 時刻・連番・実時間を取り出します。
    /// - Parameter point: 点。
    /// - Returns: 印。
    private static func mark(of point: RoadRegulationTrackPoint) -> RoadRegulationTransitionMark {
        RoadRegulationTransitionMark(time: point.time, sequence: point.sequence, observedAt: point.observedAt)
    }
}
