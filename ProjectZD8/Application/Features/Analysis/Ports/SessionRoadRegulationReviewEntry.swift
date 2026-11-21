import Foundation

/// 1件の判定(1区間または1地点)です。
nonisolated struct SessionRoadRegulationReviewEntry: Equatable, Sendable {
    /// 規制の種類です。
    let kind: SessionRoadRegulationReviewKind
    /// 判定の分類です。
    let outcome: SessionRoadRegulationReviewOutcome
    /// 判定の文言のローカライズキーです(判定できない時は理由のキー)。
    let verdictKey: String
    /// 判定できない理由です。`outcome` が `.undeterminable` の時だけ `nil` 以外です。
    let undeterminedReason: RoadRegulationUndeterminedReason?
    /// 区間の始まり(一時停止は接近の始まり)の印です。
    let start: RoadRegulationTransitionMark
    /// 区間の終わり(一時停止は停止線への到達)の印です。
    let end: RoadRegulationTransitionMark
    /// 判定に添える数値です。
    let figures: SessionRoadRegulationReviewFigures
}
