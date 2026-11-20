import Foundation

/// 一時停止の停止点への接近を、停止点 S と進入方向の点 E_i の組ごとに追います。
///
/// u = (S − E_i) の単位ベクトル、P をいまの点として、s = (P − S)·u(到達前が負)、l = 横方向の距離の絶対値です。
/// |S − E_i| が `minimumStopApproachVectorMeters` 未満の進入方向は向きが決まらないので追いません。
/// - 開始: −`stopApproachLengthMeters` ≤ s < −`stopReachMeters`、l ≤ 許容、角度差(向き, 方位(E→S)) ≤ `stopHeadingDegrees`
///   (向きが分からない時は開始しない)、再検出の待ちでない、条件が `doesNotApply` でない。
/// - 到達: s ≥ −`stopReachMeters` かつ l ≤ 許容 + `stopAbandonExtraMeters`。到達した一時停止は再検出の待ちに入ります。
/// - 打ち切り: s < −(`stopApproachLengthMeters` + `stopAbandonExtraMeters`)、l > 許容 + `stopAbandonExtraMeters`、
///   角度差 > `stopAbandonHeadingDegrees`(向きが分かる時だけ)、または候補から一時停止が消えた。
/// - 再検出の待ちは、停止点から `stopRearmDistanceMeters` を超えて離れたら解除します。
/// 1つの一時停止の到達は1歩で1回だけ数え、同じ一時停止のほかの進入方向の接近は打ち切ります。
nonisolated struct StopApproachTracker: Sendable {
    /// 進行中の接近の1歩の結果です。
    private enum ApproachProgress {
        /// 接近を続ける。
        case continuing
        /// 停止点へ到達した。
        case reached
        /// 接近を打ち切る。
        case abandoned
    }

    /// 停止点から見た、いまの点の位置です。
    private struct ApproachMeasurement {
        /// 停止点の座標。
        let stopCoordinate: GeoCoordinate
        /// 進入方向に沿った位置 s(m。到達前が負)。
        let along: Double
        /// 横方向の距離 l(m)。
        let lateral: Double
        /// 進入方向の点から停止点への方位(度)。
        let approachBearing: Double
    }

    /// 1歩の途中経過(新しい状態の材料と、出した変化)です。
    private struct StepAccumulator {
        /// 続いている接近。
        var activeApproaches: [StopApproachKey: StopApproachTrackerState.ActiveApproach] = [:]
        /// 再検出の待ち。
        var rearmWaitingStops: [RoadRegulationID: GeoCoordinate]
        /// この歩で到達した一時停止。
        var reachedStops = Set<RoadRegulationID>()
        /// 出した変化(出した順)。
        var changes: [RoadRegulationChange] = []
    }

    /// しきい値です。
    private let thresholds: RoadRegulationMatchingThresholds
    /// 方位と距離の計算器です。
    private let distanceCalculator = GeoDistanceCalculator()

    /// しきい値を決めて追跡器を作ります。
    ///
    /// 責務: 接近・到達・打ち切り・再検出の基準を保持します。
    /// - Parameter thresholds: しきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 1点ぶん一時停止の追跡を進めます。
    ///
    /// 責務: 再検出の待ちを解除し、進行中の接近の到達・打ち切りを決めてから、新しい接近を始めます。
    /// - Parameters:
    ///   - state: 直前の状態。
    ///   - point: いまの点(使える点)。
    ///   - heading: 進む向き(度)。分からなければ `nil`。
    ///   - candidates: 周辺の規制。一時停止でないものは無視します。
    ///   - applicability: 規制の条件がその時刻に当てはまるかを返す関数。
    /// - Returns: 新しい状態と、出した変化(到達・打ち切り、開始の順。それぞれ行 ID・進入方向の添字の昇順)。
    func step(
        _ state: StopApproachTrackerState,
        point: RoadRegulationTrackPoint,
        heading: Double?,
        candidates: [RoadRegulation],
        applicability: (RoadRegulation, Date) -> RegulationApplicability
    ) -> (StopApproachTrackerState, [RoadRegulationChange]) {
        let stops = candidates.filter { $0.kind == .stop }.sorted { $0.id < $1.id }
        var accumulator = StepAccumulator(rearmWaitingStops: state.rearmWaitingStops.filter { _, stop in
            distanceCalculator.distanceMeters(stop, point.coordinate) <= thresholds.stopRearmDistanceMeters
        })
        advanceActiveApproaches(state, point: point, heading: heading, stops: stops, into: &accumulator)
        startApproaches(point: point, heading: heading, stops: stops, applicability: applicability, into: &accumulator)
        let newState = StopApproachTrackerState(
            activeApproaches: accumulator.activeApproaches,
            rearmWaitingStops: accumulator.rearmWaitingStops
        )
        return (newState, accumulator.changes)
    }

    /// 記録の空白で、進行中の接近をすべて到達扱いにします。
    ///
    /// 責務: 進行中の接近ごとに、最後に使えた点で到達した `interruptedByGap = true` の通過を出し、
    /// その一時停止を再検出の待ちに入れます。同じ一時停止の2つ目以降の接近は打ち切ります。
    /// - Parameters:
    ///   - state: 直前の状態。
    ///   - lastUsable: 最後に使えた点の印。
    /// - Returns: 新しい状態(進行中の接近なし)と、出した変化。
    func interruptAll(
        _ state: StopApproachTrackerState,
        lastUsable: RoadRegulationTransitionMark
    ) -> (StopApproachTrackerState, [RoadRegulationChange]) {
        var accumulator = StepAccumulator(rearmWaitingStops: state.rearmWaitingStops)
        for key in state.activeApproachKeys {
            guard let approach = state.activeApproaches[key] else { continue }
            guard !accumulator.reachedStops.contains(key.regulationID) else {
                accumulator.changes.append(.stopApproachAbandoned(key))
                continue
            }
            record(passageOf: key, approach: approach, reached: lastUsable, interruptedByGap: true, into: &accumulator)
        }
        return (StopApproachTrackerState(activeApproaches: [:], rearmWaitingStops: accumulator.rearmWaitingStops), accumulator.changes)
    }

    /// 進行中の接近ごとに、続ける・到達・打ち切りを決めます。
    ///
    /// 責務: 候補から消えた一時停止と、同じ歩で既に到達した一時停止の接近は打ち切り、それ以外は位置で決めます。
    /// - Parameters:
    ///   - state: 直前の状態。
    ///   - point: いまの点。
    ///   - heading: 進む向き(度)。分からなければ `nil`。
    ///   - stops: 周辺の一時停止(行 ID の昇順)。
    ///   - accumulator: 途中経過。
    private func advanceActiveApproaches(
        _ state: StopApproachTrackerState,
        point: RoadRegulationTrackPoint,
        heading: Double?,
        stops: [RoadRegulation],
        into accumulator: inout StepAccumulator
    ) {
        let mark = Self.mark(of: point)
        for key in state.activeApproachKeys {
            guard let approach = state.activeApproaches[key] else { continue }
            let measurement = stops.first { $0.id == key.regulationID }
                .flatMap { measure($0, approachIndex: key.approachIndex, at: point.coordinate) }
            guard let measurement, !accumulator.reachedStops.contains(key.regulationID) else {
                accumulator.changes.append(.stopApproachAbandoned(key))
                continue
            }
            switch progress(measurement, heading: heading, accuracy: point.horizontalAccuracyMeters) {
            case .continuing: accumulator.activeApproaches[key] = approach
            case .reached: record(passageOf: key, approach: approach, reached: mark, interruptedByGap: false, into: &accumulator)
            case .abandoned: accumulator.changes.append(.stopApproachAbandoned(key))
            }
        }
        abandonContinuingApproachesOfReachedStops(into: &accumulator)
    }

    /// この歩で到達した一時停止の、続いているほかの進入方向の接近を打ち切ります。
    ///
    /// 責務: 1つの一時停止の到達を1回だけ数えるため、同じ一時停止の残りの接近を取り除いて打ち切りを出します。
    /// - Parameter accumulator: 途中経過。
    private func abandonContinuingApproachesOfReachedStops(into accumulator: inout StepAccumulator) {
        let reached = accumulator.reachedStops
        let keys = accumulator.activeApproaches.keys
            .filter { reached.contains($0.regulationID) }
            .sorted { ($0.regulationID.rawValue, $0.approachIndex) < ($1.regulationID.rawValue, $1.approachIndex) }
        for key in keys {
            accumulator.activeApproaches[key] = nil
            accumulator.changes.append(.stopApproachAbandoned(key))
        }
    }

    /// 開始の条件を満たす進入方向の接近を始めます。
    ///
    /// 責務: 向きが分かる時だけ、進行中でなく再検出の待ちでもない一時停止の進入方向ごとに、開始の条件を確かめます。
    /// - Parameters:
    ///   - point: いまの点。
    ///   - heading: 進む向き(度)。分からなければ開始しません。
    ///   - stops: 周辺の一時停止(行 ID の昇順)。
    ///   - applicability: 規制の条件がその時刻に当てはまるかを返す関数。
    ///   - accumulator: 途中経過。
    private func startApproaches(
        point: RoadRegulationTrackPoint,
        heading: Double?,
        stops: [RoadRegulation],
        applicability: (RoadRegulation, Date) -> RegulationApplicability,
        into accumulator: inout StepAccumulator
    ) {
        guard let heading, heading.isFinite else { return }
        let tolerance = thresholds.stopLateralTolerance(accuracy: point.horizontalAccuracyMeters)
        for stop in stops where accumulator.rearmWaitingStops[stop.id] == nil {
            for index in stop.geometry.approachPoints.indices {
                let key = StopApproachKey(regulationID: stop.id, approachIndex: index)
                guard accumulator.activeApproaches[key] == nil,
                      let measurement = measure(stop, approachIndex: index, at: point.coordinate),
                      canStart(measurement, heading: heading, tolerance: tolerance)
                else { continue }
                let condition = applicability(stop, point.observedAt)
                guard condition != .doesNotApply else { continue }
                let approach = StopApproachTrackerState.ActiveApproach(
                    started: Self.mark(of: point),
                    applicability: condition,
                    stopCoordinate: measurement.stopCoordinate
                )
                accumulator.activeApproaches[key] = approach
                accumulator.changes.append(.stopApproachStarted(key, approach.started))
            }
        }
    }

    /// 到達した通過を出し、その一時停止を再検出の待ちに入れます。
    ///
    /// 責務: 開始時の印と条件の判定で `StopPassage` を作って変化に加えます。
    /// - Parameters:
    ///   - key: 一時停止と進入方向。
    ///   - approach: 進行中の接近。
    ///   - reached: 到達した点の印。
    ///   - interruptedByGap: 記録の空白で到達扱いにしたか。
    ///   - accumulator: 途中経過。
    private func record(
        passageOf key: StopApproachKey,
        approach: StopApproachTrackerState.ActiveApproach,
        reached: RoadRegulationTransitionMark,
        interruptedByGap: Bool,
        into accumulator: inout StepAccumulator
    ) {
        let passage = StopPassage(
            key: key,
            approachStarted: approach.started,
            reached: reached,
            applicability: approach.applicability,
            interruptedByGap: interruptedByGap
        )
        accumulator.changes.append(.stopReached(passage))
        accumulator.reachedStops.insert(key.regulationID)
        accumulator.rearmWaitingStops[key.regulationID] = approach.stopCoordinate
    }

    /// 開始の条件を満たすかを返します。
    ///
    /// 責務: −接近の長さ ≤ s < −到達の距離、l ≤ 許容、角度差(向き, 方位(E→S)) ≤ 開始の角度を確かめます。
    /// - Parameters:
    ///   - measurement: 停止点から見た位置。
    ///   - heading: 進む向き(度)。
    ///   - tolerance: 一時停止の横方向の許容(m)。
    /// - Returns: 開始してよければ `true`。
    private func canStart(_ measurement: ApproachMeasurement, heading: Double, tolerance: Double) -> Bool {
        let isInWindow = measurement.along >= -thresholds.stopApproachLengthMeters && measurement.along < -thresholds.stopReachMeters
        let headingDifference = distanceCalculator.angularDifference(heading, measurement.approachBearing)
        return isInWindow && measurement.lateral <= tolerance && headingDifference <= thresholds.stopHeadingDegrees
    }

    /// 進行中の接近の、この点での結果を返します。
    ///
    /// 責務: 到達の条件を先に確かめ、次に範囲・横方向・向きの外れで打ち切りを決めます。
    /// - Parameters:
    ///   - measurement: 停止点から見た位置。
    ///   - heading: 進む向き(度)。分からなければ向きでは打ち切りません。
    ///   - accuracy: 点の水平精度(m)。
    /// - Returns: 続ける・到達・打ち切りのどれか。
    private func progress(_ measurement: ApproachMeasurement, heading: Double?, accuracy: Double) -> ApproachProgress {
        let lateralLimit = thresholds.stopLateralTolerance(accuracy: accuracy) + thresholds.stopAbandonExtraMeters
        if measurement.along >= -thresholds.stopReachMeters && measurement.lateral <= lateralLimit { return .reached }
        let isBeyondWindow = measurement.along < -(thresholds.stopApproachLengthMeters + thresholds.stopAbandonExtraMeters)
        let isTurnedAway = heading.map {
            $0.isFinite && distanceCalculator.angularDifference($0, measurement.approachBearing) > thresholds.stopAbandonHeadingDegrees
        } ?? false
        return isBeyondWindow || measurement.lateral > lateralLimit || isTurnedAway ? .abandoned : .continuing
    }

    /// 停止点から見たいまの点の位置を求めます。
    ///
    /// 責務: 停止点を原点にした平面で、進入方向の単位ベクトルに沿った位置と横方向の距離を求めます。
    /// - Parameters:
    ///   - stop: 一時停止の規制。
    ///   - approachIndex: 進入方向の点の添字。
    ///   - coordinate: いまの点の位置。
    /// - Returns: 位置。停止点・進入方向の点が無い時と、2点が近すぎて向きが決まらない時は `nil`。
    private func measure(_ stop: RoadRegulation, approachIndex: Int, at coordinate: GeoCoordinate) -> ApproachMeasurement? {
        let approachPoints = stop.geometry.approachPoints
        guard let stopCoordinate = stop.geometry.mainParts.first?.first,
              approachPoints.indices.contains(approachIndex)
        else { return nil }
        let entry = approachPoints[approachIndex]
        let projection = GeoLocalProjection(origin: stopCoordinate)
        let entryPoint = projection.project(entry)
        let length = (entryPoint.x * entryPoint.x + entryPoint.y * entryPoint.y).squareRoot()
        guard length >= thresholds.minimumStopApproachVectorMeters,
              let bearing = distanceCalculator.bearingDegrees(from: entry, to: stopCoordinate)
        else { return nil }
        let unitX = -entryPoint.x / length
        let unitY = -entryPoint.y / length
        let position = projection.project(coordinate)
        return ApproachMeasurement(
            stopCoordinate: stopCoordinate,
            along: position.x * unitX + position.y * unitY,
            lateral: abs(position.x * unitY - position.y * unitX),
            approachBearing: bearing
        )
    }

    /// 軌跡の点の印を作ります。
    ///
    /// 責務: 時刻・連番・実時間を写します。
    /// - Parameter point: 軌跡の点。
    /// - Returns: 点の印。
    private static func mark(of point: RoadRegulationTrackPoint) -> RoadRegulationTransitionMark {
        RoadRegulationTransitionMark(time: point.time, sequence: point.sequence, observedAt: point.observedAt)
    }
}
