import Foundation

/// 1回の取り込みで数えた行の件数です。
nonisolated struct RoadRegulationImportCounts: Equatable, Sendable {
    /// CSV のデータ行の総数。
    let totalRows: Int
    /// 保存した規制の件数。
    let importedRegulations: Int
    /// 対象外の種別として飛ばした件数。
    let skippedOutOfScope: Int
    /// 廃止済みとして飛ばした件数。
    let skippedAbolished: Int
    /// 捨てた理由ごとの件数。
    let rejectedByReason: [RoadRegulationRowRejection: Int]

    /// 捨てた行の合計です。
    var rejectedRows: Int {
        rejectedByReason.values.reduce(0, +)
    }
}
