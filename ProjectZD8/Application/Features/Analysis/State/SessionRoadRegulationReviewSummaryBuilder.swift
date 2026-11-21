import Foundation

/// 一覧の行から、規制の種類ごとのまとめを作ります。
///
/// まとめは常に4件(`SessionRoadRegulationReviewKind.allCases` の順)で、件数は分類ごと(`SessionRoadRegulationReviewOutcome.allCases` の順、0件は入れない)です。
nonisolated struct SessionRoadRegulationReviewSummaryBuilder: Sendable {
    /// キーと色の分類の表引きです。
    private let keys: SessionRoadRegulationReviewTextKeys

    /// 表引きを受け取って作ります。
    ///
    /// 責務: 種類名・ラベル・色の分類の表引きを保持します。
    /// - Parameter keys: キーと色の分類の表引き。
    init(keys: SessionRoadRegulationReviewTextKeys = .init()) {
        self.keys = keys
    }

    /// 種類ごとのまとめを作ります。
    ///
    /// 責務: 4つの種類それぞれについて、行の数と分類ごとの件数をまとめます。
    /// - Parameter rows: 一覧の行。
    /// - Returns: 種類ごとのまとめ(常に4件)。
    func summaries(for rows: [SessionRoadRegulationReviewRow]) -> [SessionRoadRegulationReviewKindSummary] {
        SessionRoadRegulationReviewKind.allCases.map { kind in
            summary(kind: kind, rows: rows.filter { $0.kind == kind })
        }
    }

    /// 1つの種類のまとめを作ります。
    ///
    /// 責務: その種類の行の数と、1件以上ある分類の件数を並べます。
    /// - Parameters:
    ///   - kind: 規制の種類。
    ///   - rows: その種類の行。
    /// - Returns: まとめ。
    private func summary(kind: SessionRoadRegulationReviewKind, rows: [SessionRoadRegulationReviewRow]) -> SessionRoadRegulationReviewKindSummary {
        let counts = SessionRoadRegulationReviewOutcome.allCases.compactMap { outcome in
            count(kind: kind, outcome: outcome, number: rows.filter { $0.outcome == outcome }.count)
        }
        return SessionRoadRegulationReviewKindSummary(kind: kind, titleKey: keys.kindTitleKey(for: kind), total: rows.count, counts: counts)
    }

    /// 1つの分類の件数を作ります。
    ///
    /// 責務: 件数が1以上の時だけ、ラベルのキーと色の分類を添えた件数を返します。
    /// - Parameters:
    ///   - kind: 規制の種類。
    ///   - outcome: 判定の分類。
    ///   - number: 件数。
    /// - Returns: 件数。0件なら `nil`。
    private func count(
        kind: SessionRoadRegulationReviewKind,
        outcome: SessionRoadRegulationReviewOutcome,
        number: Int
    ) -> SessionRoadRegulationReviewCount? {
        guard number > 0 else { return nil }
        return SessionRoadRegulationReviewCount(
            outcome: outcome,
            labelKey: keys.outcomeLabelKey(kind: kind, outcome: outcome),
            category: keys.category(for: outcome),
            count: number
        )
    }
}
