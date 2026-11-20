import Foundation

/// 取り込みで CSV の行を対象外として飛ばした理由です(捨てた行には数えません)。
nonisolated enum RoadRegulationRowSkipReason: String, Sendable {
    /// 判定に使わない種別。
    case outOfScopeKind
    /// 廃止済みの規制。
    case abolished
}
