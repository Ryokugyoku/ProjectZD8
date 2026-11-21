import Foundation

/// 1回の走行の軌跡・車速・規制から、規制の判定結果を作ります(純粋な計算)。
///
/// 軌跡の全点を順に `RoadRegulationMatcher` へ流し、`RoadRegulationTraversalRecorder` で区間と一時停止の通過にまとめ、
/// 4つの判定器で判定してから `SessionRoadRegulationReportBuilder` で集計します。
/// 走行中に同じ matcher を使う時も、保存済みの軌跡を順に流せば同じ結果になります。
nonisolated struct SessionRoadRegulationEvaluator: Sendable {
    /// 区間と一時停止の通過を記録した結果です。
    private struct Recording {
        /// 区間(閉じた順)。
        let traversals: [RoadRegulationTraversal]
        /// 一時停止の通過。
        let stopPassages: [StopPassage]
        /// 候補に現れた一方通行の規制(区間の長さを求めるのに使う)。
        let oneWayRegulations: [RoadRegulationID: RoadRegulation]
    }

    /// しきい値です(軌跡を作る時にも同じ値を使えるよう公開します)。
    let thresholds: RoadRegulationMatchingThresholds
    /// 1点ずつの突き合わせです。
    private let matcher: RoadRegulationMatcher
    /// 最高速度の判定器です。
    private let speedLimitJudge: SpeedLimitJudge
    /// 一時停止の判定器です。
    private let stopJudge: StopJudge
    /// 一方通行の判定器です。
    private let oneWayJudge: OneWayJudge
    /// 徐行の判定器です。
    private let slowDownJudge: SlowDownJudge
    /// 線の長さの計算器です。
    private let proximityCalculator = GeoPolylineProximityCalculator()

    /// しきい値と車の種類を決めて評価器を作ります。
    ///
    /// 責務: matcher と4つの判定器を、同じしきい値で用意します。
    /// - Parameters:
    ///   - thresholds: しきい値。
    ///   - vehicleClass: 条件の判定に使う車の種類。
    init(thresholds: RoadRegulationMatchingThresholds = .standard, vehicleClass: RegulationVehicleClass = .standardPassenger) {
        self.thresholds = thresholds
        self.matcher = RoadRegulationMatcher(thresholds: thresholds, applicability: .init(vehicleClass: vehicleClass))
        self.speedLimitJudge = SpeedLimitJudge(thresholds: thresholds)
        self.stopJudge = StopJudge(thresholds: thresholds)
        self.oneWayJudge = OneWayJudge(thresholds: thresholds)
        self.slowDownJudge = SlowDownJudge(thresholds: thresholds)
    }

    /// 1回の走行を判定します。
    ///
    /// 責務: 軌跡を突き合わせて区間と一時停止の通過を作り、種類ごとに判定して、入力の範囲と質を添えて集計します。
    /// - Parameters:
    ///   - track: 使える軌跡の点(時刻の昇順)。
    ///   - droppedPointCount: 軌跡を作る時に捨てた点の数。
    ///   - speeds: 車速の時系列(同じ時刻の軸)。
    ///   - index: 規制の索引。
    ///   - coverage: 取得済みの版の範囲(外接矩形)。
    ///   - timeAxis: 選んだ時刻の軸。
    ///   - datasets: 使った規制データの版。
    /// - Returns: 走行の判定結果。
    func evaluate(
        track: [RoadRegulationTrackPoint],
        droppedPointCount: Int,
        speeds: VehicleSpeedTimeline,
        index: RoadRegulationSpatialIndex,
        coverage: [GeoBoundingBox],
        timeAxis: RoadRegulationTimeAxis,
        datasets: [RoadRegulationDatasetReference]
    ) -> SessionRoadRegulationReport {
        let recording = record(track: track, index: index, coverage: coverage)
        let speedLimit = recording.traversals.filter(Self.isSpeedLimit).map { speedLimitJudge.judge($0, speeds: speeds) }
        let stops = recording.stopPassages.map { stopJudge.judge($0, speeds: speeds) }
        let oneWay = judgeOneWay(recording, track: track)
        let slowDown = recording.traversals.filter(Self.isSlowDown).map { slowDownJudge.judge($0, speeds: speeds) }
        let evaluationCoverage = RoadRegulationEvaluationCoverage(
            timeAxis: timeAxis,
            trackPointCount: track.count,
            droppedPointCount: droppedPointCount,
            hasVehicleSpeed: !speeds.isEmpty,
            datasets: datasets
        )
        return SessionRoadRegulationReportBuilder().build(
            speedLimit: speedLimit,
            stops: stops,
            oneWay: oneWay,
            slowDown: slowDown,
            coverage: evaluationCoverage
        )
    }

    /// 軌跡の全点を matcher へ流して記録します。
    ///
    /// 責務: 点ごとに周辺の規制と範囲の内外を求めて1歩進め、記録器へ渡し、候補に現れた一方通行の規制を集めます。
    /// - Parameters:
    ///   - track: 軌跡の点。
    ///   - index: 規制の索引。
    ///   - coverage: 版の範囲。
    /// - Returns: 区間・一時停止の通過・一方通行の規制。
    private func record(track: [RoadRegulationTrackPoint], index: RoadRegulationSpatialIndex, coverage: [GeoBoundingBox]) -> Recording {
        var state = RoadRegulationMatchState.initial
        var recorder = RoadRegulationTraversalRecorder()
        var oneWayRegulations: [RoadRegulationID: RoadRegulation] = [:]
        for point in track {
            let regulations = index.candidates(around: point.coordinate, radiusMeters: thresholds.searchRadiusMeters)
            let context = RoadRegulationCandidateContext(
                regulations: regulations,
                isInsideDataCoverage: coverage.contains { $0.contains(point.coordinate) }
            )
            let step = matcher.step(from: state, point: point, context: context)
            recorder.record(step, point: point)
            state = step.state
            for regulation in regulations where regulation.kind == .oneWay {
                oneWayRegulations[regulation.id] = regulation
            }
        }
        let finished = recorder.finish()
        return Recording(traversals: finished.traversals, stopPassages: finished.stopPassages, oneWayRegulations: oneWayRegulations)
    }

    /// 一方通行の区間を判定します。
    ///
    /// 責務: 区間ごとに、区間の連番の範囲の点と規制区間の長さを判定器へ渡します。
    /// - Parameters:
    ///   - recording: 記録の結果。
    ///   - track: 軌跡の点。
    /// - Returns: 一方通行の判定(区間の順)。
    private func judgeOneWay(_ recording: Recording, track: [RoadRegulationTrackPoint]) -> [OneWayJudgement] {
        let traversals = recording.traversals.filter(Self.isOneWay)
        guard !traversals.isEmpty else { return [] }
        let positions = Dictionary(track.enumerated().map { ($1.sequence, $0) }, uniquingKeysWith: { first, _ in first })
        return traversals.map { traversal in
            let lower = positions[traversal.start.sequence] ?? track.startIndex
            let upper = positions[traversal.end.sequence] ?? (track.endIndex - 1)
            let slice = lower <= upper ? track[lower...upper] : track[...]
            return oneWayJudge.judge(traversal, track: slice, regulationLengthMeters: regulationLength(of: traversal, in: recording))
        }
    }

    /// 一方通行の区間の規制の長さを返します。
    ///
    /// 責務: 区間の規制の、規制場所の全区間の長さの合計を求めます。規制が分からなければ 0 を返します。
    /// - Parameters:
    ///   - traversal: 一方通行の区間。
    ///   - recording: 記録の結果。
    /// - Returns: 長さ(m)。
    private func regulationLength(of traversal: RoadRegulationTraversal, in recording: Recording) -> Double {
        guard case .oneWay(.on(let id, _)) = traversal.status, let regulation = recording.oneWayRegulations[id] else { return 0 }
        return regulation.geometry.mainParts.reduce(0) { $0 + proximityCalculator.pathLengthMeters($1) }
    }

    /// 最高速度の経路の区間かを返します。
    ///
    /// 責務: 区間の状態の種類を確かめます。
    /// - Parameter traversal: 区間。
    /// - Returns: 最高速度の経路なら `true`。
    private static func isSpeedLimit(_ traversal: RoadRegulationTraversal) -> Bool {
        if case .speedLimit = traversal.status { return true }
        return false
    }

    /// 一方通行の経路の区間かを返します。
    ///
    /// 責務: 区間の状態の種類を確かめます。
    /// - Parameter traversal: 区間。
    /// - Returns: 一方通行の経路なら `true`。
    private static func isOneWay(_ traversal: RoadRegulationTraversal) -> Bool {
        if case .oneWay = traversal.status { return true }
        return false
    }

    /// 徐行の経路の区間かを返します。
    ///
    /// 責務: 区間の状態の種類を確かめます。
    /// - Parameter traversal: 区間。
    /// - Returns: 徐行の経路なら `true`。
    private static func isSlowDown(_ traversal: RoadRegulationTraversal) -> Bool {
        if case .slowDown = traversal.status { return true }
        return false
    }
}
