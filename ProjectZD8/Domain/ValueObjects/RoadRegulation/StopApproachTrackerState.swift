import Foundation

/// 一時停止の追跡の状態(進行中の接近と、再び検出してよくなるまでの待ち)です。
nonisolated struct StopApproachTrackerState: Equatable, Sendable {
    /// 進行中の接近も待ちも無い状態です。
    static let initial = StopApproachTrackerState(approachStarts: [:], approachApplicabilities: [:], rearmWaitingStops: [:])

    /// 進行中の接近と、接近を始めた点。
    let approachStarts: [StopApproachKey: RoadRegulationTransitionMark]
    /// 進行中の接近の、開始時の条件の判定(`applies` または `unknown`)。
    let approachApplicabilities: [StopApproachKey: RegulationApplicability]
    /// 到達済みで再び検出するのを待つ一時停止と、その停止点。
    let rearmWaitingStops: [RoadRegulationID: GeoCoordinate]

    /// 進行中の接近を、規制の行 ID と進入方向の添字の昇順で並べたものです。
    var activeApproachKeys: [StopApproachKey] {
        approachStarts.keys.sorted { ($0.regulationID.rawValue, $0.approachIndex) < ($1.regulationID.rawValue, $1.approachIndex) }
    }
}
