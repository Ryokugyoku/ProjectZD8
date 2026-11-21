import Foundation

/// 一覧の行を、規制の種類ごとの区分へ分け、表示の切替で絞り込みます。
///
/// 区分は常に4件(`SessionRoadRegulationReviewKind.allCases` の順)です。行が無い区分には、空の理由の文言のキーを添えます。
nonisolated struct SessionRoadRegulationReviewSectionBuilder: Sendable {
    /// キーの表引きです。
    private let keys: SessionRoadRegulationReviewTextKeys

    /// 表引きを受け取って作ります。
    ///
    /// 責務: 種類名と空の文言のキーの表引きを保持します。
    /// - Parameter keys: キーの表引き。
    init(keys: SessionRoadRegulationReviewTextKeys = .init()) {
        self.keys = keys
    }

    /// 種類ごとの区分を作ります。
    ///
    /// 責務: 4つの種類それぞれについて、絞り込んだ行と絞り込み前の件数をまとめます。
    /// - Parameters:
    ///   - rows: 一覧の行。
    ///   - filter: 表示の切替。
    /// - Returns: 種類ごとの区分(常に4件)。
    func sections(for rows: [SessionRoadRegulationReviewRow], filter: SessionRoadRegulationReviewFilter) -> [SessionRoadRegulationReviewSection] {
        SessionRoadRegulationReviewKind.allCases.map { kind in
            section(kind: kind, rows: rows.filter { $0.kind == kind }, filter: filter)
        }
    }

    /// 行がどれかの区分に見えているかを返します。
    ///
    /// 責務: どれかの区分の行にその ID があるかを調べます。
    /// - Parameters:
    ///   - rowID: 行の ID。
    ///   - sections: 区分。
    /// - Returns: 見えているなら `true`。
    func isVisible(rowID: Int, in sections: [SessionRoadRegulationReviewSection]) -> Bool {
        sections.contains { section in section.rows.contains { $0.id == rowID } }
    }

    /// 1つの種類の区分を作ります。
    ///
    /// 責務: 絞り込んだ行を ID の昇順に並べ、行が無い時は空の理由のキーを選びます。
    /// - Parameters:
    ///   - kind: 規制の種類。
    ///   - rows: その種類の全行。
    ///   - filter: 表示の切替。
    /// - Returns: 区分。
    private func section(
        kind: SessionRoadRegulationReviewKind,
        rows: [SessionRoadRegulationReviewRow],
        filter: SessionRoadRegulationReviewFilter
    ) -> SessionRoadRegulationReviewSection {
        let visible = rows.filter { filter.includes($0.outcome) }.sorted { $0.id < $1.id }
        return SessionRoadRegulationReviewSection(
            kind: kind,
            titleKey: keys.kindTitleKey(for: kind),
            totalCount: rows.count,
            rows: visible,
            emptyMessageKey: emptyMessageKey(visibleCount: visible.count, totalCount: rows.count)
        )
    }

    /// 行が無い時の文言のキーを選びます。
    ///
    /// 責務: 行があれば `nil`、種類の通過が0件なら通過なしの、絞り込みで0件なら確認不要のキーを返します。
    /// - Parameters:
    ///   - visibleCount: 絞り込み後の件数。
    ///   - totalCount: 絞り込み前の件数。
    /// - Returns: ローカライズキー。行があれば `nil`。
    private func emptyMessageKey(visibleCount: Int, totalCount: Int) -> String? {
        guard visibleCount == 0 else { return nil }
        return totalCount == 0 ? keys.emptyKindKey : keys.emptyFilteredKey
    }
}
