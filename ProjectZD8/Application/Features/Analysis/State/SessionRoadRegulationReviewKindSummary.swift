import Foundation

/// 「まとめ」の1種類分のタイルです。
nonisolated struct SessionRoadRegulationReviewKindSummary: Identifiable, Equatable, Sendable {
    /// 規制の種類です。
    let kind: SessionRoadRegulationReviewKind
    /// 種類名のローカライズキーです。
    let titleKey: String
    /// 通過した区間・地点の数です。
    let total: Int
    /// 判定の分類ごとの件数です(分類の宣言順。件数0は入れません)。
    let counts: [SessionRoadRegulationReviewCount]

    /// 一覧で使用する安定識別子(規制の種類)です。
    var id: SessionRoadRegulationReviewKind { kind }
}
