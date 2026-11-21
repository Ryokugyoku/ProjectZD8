import Foundation

/// 「まとめ」の1種類の中の、判定の分類ごとの件数です。
nonisolated struct SessionRoadRegulationReviewCount: Identifiable, Equatable, Sendable {
    /// 判定の分類です。
    let outcome: SessionRoadRegulationReviewOutcome
    /// 分類のラベルのローカライズキーです。
    let labelKey: String
    /// 色見本の色の分類です。
    let category: RouteAnalysisColorCategory
    /// 件数です(1以上)。
    let count: Int

    /// 一覧で使用する安定識別子(判定の分類)です。
    var id: SessionRoadRegulationReviewOutcome { outcome }
}
