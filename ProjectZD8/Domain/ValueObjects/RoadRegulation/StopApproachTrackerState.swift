import Foundation

/// 一時停止の追跡の状態(進行中の接近と、再び検出してよくなるまでの待ち)です。
nonisolated struct StopApproachTrackerState: Equatable, Sendable {
    /// 進行中の1つの接近です。
    nonisolated struct ActiveApproach: Equatable, Sendable {
        /// 接近を始めた点。
        let started: RoadRegulationTransitionMark
        /// 開始時の条件の判定(`applies` または `unknown`)。
        let applicability: RegulationApplicability
        /// 一時停止の停止点(空白で打ち切った後の再検出の待ちに使う)。
        let stopCoordinate: GeoCoordinate
    }

    /// 進行中の接近も待ちも無い状態です。
    static let initial = StopApproachTrackerState(activeApproaches: [:], rearmWaitingStops: [:])

    /// 進行中の接近。
    let activeApproaches: [StopApproachKey: ActiveApproach]
    /// 到達済みで再び検出するのを待つ一時停止と、その停止点。
    let rearmWaitingStops: [RoadRegulationID: GeoCoordinate]

    /// 進行中の接近と、接近を始めた点です。
    var approachStarts: [StopApproachKey: RoadRegulationTransitionMark] {
        activeApproaches.mapValues(\.started)
    }

    /// 進行中の接近の、開始時の条件の判定(`applies` または `unknown`)です。
    var approachApplicabilities: [StopApproachKey: RegulationApplicability] {
        activeApproaches.mapValues(\.applicability)
    }

    /// 進行中の接近を、規制の行 ID と進入方向の添字の昇順で並べたものです。
    var activeApproachKeys: [StopApproachKey] {
        activeApproaches.keys.sorted { ($0.regulationID.rawValue, $0.approachIndex) < ($1.regulationID.rawValue, $1.approachIndex) }
    }
}
