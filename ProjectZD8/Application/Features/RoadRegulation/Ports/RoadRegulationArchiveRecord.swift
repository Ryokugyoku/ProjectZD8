import Foundation

/// ZIP の CSV を1行解釈した結果です。
nonisolated enum RoadRegulationArchiveRecord: Equatable, Sendable {
    /// 取り込む規制。
    case regulation(RoadRegulationDraft)
    /// 対象外として飛ばした行。
    case skipped(RoadRegulationRowSkipReason)
    /// 捨てた行。
    case rejected(RoadRegulationRowRejection)
}
