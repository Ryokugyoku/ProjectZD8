import Foundation

/// 一時停止の停止点へ接近して到達した1回の通過です。
nonisolated struct StopPassage: Equatable, Sendable {
    /// 一時停止の規制と進入方向。
    let key: StopApproachKey
    /// 接近を始めた点。
    let approachStarted: RoadRegulationTransitionMark
    /// 到達した点(空白で打ち切った時は最後に使えた点)。
    let reached: RoadRegulationTransitionMark
    /// 条件の判定(`applies` または `unknown`)。
    let applicability: RegulationApplicability
    /// 記録の空白で到達扱いにしたか。
    let interruptedByGap: Bool
}
