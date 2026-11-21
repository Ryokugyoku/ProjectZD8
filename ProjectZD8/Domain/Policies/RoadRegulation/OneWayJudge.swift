import Foundation

/// 一方通行の区間の通過を、逆向きに走った距離で判定します。距離がしきい値以上の時だけ逆走の可能性とします。
nonisolated struct OneWayJudge: Sendable {
    /// 判定に使うしきい値。
    private let thresholds: RoadRegulationMatchingThresholds
    /// 2点間の距離の計算。
    private let distance = GeoDistanceCalculator()

    /// しきい値を受け取って判定器を作ります。
    ///
    /// 責務: 判定に使うしきい値を保持します。
    /// - Parameter thresholds: 逆走に必要な距離と、距離に数える点の精度のしきい値。
    init(thresholds: RoadRegulationMatchingThresholds = .standard) {
        self.thresholds = thresholds
    }

    /// 一方通行の区間1つを判定します。
    ///
    /// 責務: 区間の状態に応じて、向きどおり・逆走の可能性・判定できないのいずれかを返します。
    /// - Parameters:
    ///   - traversal: 一方通行の経路の区間。
    ///   - track: 軌跡の点(区間を含む範囲。区間の連番の外の点は使わない)。
    ///   - regulationLengthMeters: 一方通行の規制区間の長さ(m)。
    /// - Returns: 判定結果。
    func judge(
        _ traversal: RoadRegulationTraversal,
        track: ArraySlice<RoadRegulationTrackPoint>,
        regulationLengthMeters: Double
    ) -> OneWayJudgement {
        OneWayJudgement(
            traversal: traversal,
            verdict: verdict(for: traversal, track: track, regulationLengthMeters: regulationLengthMeters)
        )
    }

    /// 区間の状態から判定を選びます。
    ///
    /// 責務: 一方通行の経路の状態ごとに判定を振り分けます。
    /// - Parameters:
    ///   - traversal: 区間。
    ///   - track: 軌跡の点。
    ///   - regulationLengthMeters: 規制区間の長さ(m)。
    /// - Returns: 判定。
    private func verdict(
        for traversal: RoadRegulationTraversal,
        track: ArraySlice<RoadRegulationTrackPoint>,
        regulationLengthMeters: Double
    ) -> OneWayVerdict {
        guard case .oneWay(let status) = traversal.status else { return .undeterminable(.outsideRegulationData) }
        switch status {
        case .pending:
            return .undeterminable(.trackGap)
        case .none:
            return .undeterminable(.outsideRegulationData)
        case .undeterminable(let reason, _):
            return .undeterminable(reason)
        case .on(_, .permitted):
            return .followedDirection
        case .on(_, .reverse):
            let points = Self.points(of: traversal, in: track)
            return reverseVerdict(points, regulationLengthMeters: regulationLengthMeters)
        }
    }

    /// 逆向きに走った区間を判定します。
    ///
    /// 責務: 精度の悪い点が過半なら精度不足とし、そうでなければ精度の良い点を結んだ距離を必要な距離と比べます。
    /// - Parameters:
    ///   - points: 区間内の点(連番の順)。
    ///   - regulationLengthMeters: 規制区間の長さ(m)。
    /// - Returns: 判定。
    private func reverseVerdict(_ points: [RoadRegulationTrackPoint], regulationLengthMeters: Double) -> OneWayVerdict {
        let usable = points.filter { $0.horizontalAccuracyMeters <= thresholds.wrongWayMaximumAccuracyMeters }
        let inaccurateCount = points.count - usable.count
        if inaccurateCount * 2 > points.count {
            return .undeterminable(.lowAccuracy)
        }
        let travelled = zip(usable, usable.dropFirst()).reduce(0.0) { total, pair in
            total + distance.distanceMeters(pair.0.coordinate, pair.1.coordinate)
        }
        let required = thresholds.wrongWayRequiredDistance(regulationLengthMeters: regulationLengthMeters)
        guard travelled >= required else { return .undeterminable(.insufficientDistance) }
        return .possibleWrongWay(distanceMeters: travelled)
    }

    /// 軌跡の点のうち、区間の連番の範囲にある点を返します。
    ///
    /// 責務: 開始と終了の連番(両端を含む)の中の点を、渡された順のまま取り出します。
    /// - Parameters:
    ///   - traversal: 区間。
    ///   - track: 軌跡の点。
    /// - Returns: 区間内の点。
    private static func points(
        of traversal: RoadRegulationTraversal,
        in track: ArraySlice<RoadRegulationTrackPoint>
    ) -> [RoadRegulationTrackPoint] {
        let lower = Swift.min(traversal.start.sequence, traversal.end.sequence)
        let upper = Swift.max(traversal.start.sequence, traversal.end.sequence)
        return track.filter { (lower...upper).contains($0.sequence) }
    }
}
