import Foundation

/// 規制の当てはめや判定を「判定できない」にした理由です。
nonisolated enum RoadRegulationUndeterminedReason: String, CaseIterable, Sendable {
    /// 規制の線分が粗く、どの道か決められない。
    case coarseGeometry
    /// 結果の違う候補が僅差で並ぶ。
    case ambiguousCandidates
    /// 時間・曜日・車両などの条件が当てはまるか分からない。
    case conditionUnknown
    /// 可変の最高速度区間。
    case variableSpeedLimit
    /// 片側だけの規制区間。
    case oneSidedSection
    /// 区域の境目の近く。
    case nearZoneBoundary
    /// 除外区間・区域の近く。
    case nearExclusionArea
    /// 進む向きが分からない。
    case headingUnknown
    /// 取得済みの規制データの範囲外。
    case outsideRegulationData
    /// 車速が記録されていない。
    case speedUnavailable
    /// 車速の記録の間隔が粗い。
    case speedSamplingTooSparse
    /// 別の道路(高架と下の道路など)を取り違えた疑いがある。
    case possiblyDifferentRoad
    /// 逆走の判定に必要な距離に足りない。
    case insufficientDistance
    /// 位置の精度が低い。
    case lowAccuracy
    /// 位置の記録が途切れた。
    case trackGap
}
