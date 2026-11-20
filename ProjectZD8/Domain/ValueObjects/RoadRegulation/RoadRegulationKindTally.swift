import Foundation

/// 規制の種類ごとの判定の集計です。
nonisolated struct RoadRegulationKindTally: Equatable, Sendable {
    /// 判定の総数。
    let total: Int
    /// 判定の case 名ごとの件数。
    let verdictCounts: [String: Int]
    /// 判定できなかった件数。
    let undetermined: Int
    /// 判定できなかった理由ごとの件数。
    let undeterminedByReason: [RoadRegulationUndeterminedReason: Int]
}
