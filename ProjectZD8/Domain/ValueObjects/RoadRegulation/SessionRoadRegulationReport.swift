import Foundation

/// 1回の走行の規制の判定結果です。
nonisolated struct SessionRoadRegulationReport: Equatable, Sendable {
    /// 最高速度の判定。
    let speedLimit: [SpeedLimitJudgement]
    /// 一時停止の判定。
    let stops: [StopJudgement]
    /// 一方通行の判定。
    let oneWay: [OneWayJudgement]
    /// 徐行の判定。
    let slowDown: [SlowDownJudgement]
    /// 最高速度の集計。
    let speedLimitTally: RoadRegulationKindTally
    /// 一時停止の集計。
    let stopTally: RoadRegulationKindTally
    /// 一方通行の集計。
    let oneWayTally: RoadRegulationKindTally
    /// 徐行の集計。
    let slowDownTally: RoadRegulationKindTally
    /// 入力の範囲と質。
    let coverage: RoadRegulationEvaluationCoverage
}
