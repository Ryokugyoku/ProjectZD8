import Foundation

/// 種類ごとの一覧(見出しと、絞り込んだ行)です。
nonisolated struct SessionRoadRegulationReviewSection: Identifiable, Equatable, Sendable {
    /// 規制の種類です。
    let kind: SessionRoadRegulationReviewKind
    /// 種類名のローカライズキーです。
    let titleKey: String
    /// 絞り込み前の件数です。
    let totalCount: Int
    /// 絞り込み後の行です。
    let rows: [SessionRoadRegulationReviewRow]
    /// 行が無い時に出す文言のローカライズキーです。`rows` が空の時だけ `nil` 以外です。
    let emptyMessageKey: String?

    /// 一覧で使用する安定識別子(規制の種類)です。
    var id: SessionRoadRegulationReviewKind { kind }
}
