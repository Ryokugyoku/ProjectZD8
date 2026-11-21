import Foundation

/// 一覧の行から、段階4の地図とグラフへ渡す重ね合わせを規制の種類ごとに作ります。
///
/// - 行が1件以上ある種類だけを `SessionRoadRegulationReviewKind.allCases` の順に作ります。
/// - 色の区間は分類の優先(`SessionRoadRegulationReviewOutcome.allCases` の順)→ 行の ID の昇順に並べます(先の区間が優先)。
/// - 凡例は現れた分類を同じ順で並べ、最後に「該当する規制なし」(`.base`)を足します。
/// - 強調は、選んだ行がその種類なら その行の範囲1つ、それ以外は確認が必要な行の範囲(ID の昇順、併合しない)です。範囲は前後に余白を足します。
nonisolated struct SessionRoadRegulationReviewOverlayBuilder: Sendable {
    /// キー・色の分類の表引きです。
    private let keys: SessionRoadRegulationReviewTextKeys
    /// 強調の範囲の前後に足す秒数です(有限で 0 以上)。
    private let highlightPaddingSeconds: TimeInterval
    /// ローカライズキーを文字列へ解決する関数です。
    private let localize: @Sendable (String) -> String

    /// 表引き・強調の余白・キーの解決方法を受け取って作ります。
    ///
    /// 責務: 重ね合わせの作成に使う設定を保持します(余白は有限でない・負の値を 0 に倒します)。
    /// - Parameters:
    ///   - keys: キー・色の分類の表引き。
    ///   - highlightPaddingSeconds: 強調の範囲の前後に足す秒数。
    ///   - localize: キーを文字列へ解決する関数(既定はアプリの文字列表)。
    init(
        keys: SessionRoadRegulationReviewTextKeys = .init(),
        highlightPaddingSeconds: TimeInterval = 0.5,
        localize: @escaping @Sendable (String) -> String = { String(localized: String.LocalizationValue($0)) }
    ) {
        self.keys = keys
        self.highlightPaddingSeconds = highlightPaddingSeconds.isFinite ? max(0, highlightPaddingSeconds) : 0
        self.localize = localize
    }

    /// 種類ごとの重ね合わせを作ります。
    ///
    /// 責務: 行のある種類だけについて、色の区間・凡例・強調の範囲をまとめます。
    /// - Parameters:
    ///   - rows: 一覧の行。
    ///   - selectedRowID: 選んでいる行の ID。選んでいなければ `nil`。
    /// - Returns: 重ね合わせ(行が無ければ空)。
    func overlays(for rows: [SessionRoadRegulationReviewRow], selectedRowID: Int?) -> [RouteAnalysisOverlay] {
        let selectedRow = selectedRowID.flatMap { id in rows.first { $0.id == id } }
        return SessionRoadRegulationReviewKind.allCases.compactMap { kind in
            overlay(kind: kind, rows: rows.filter { $0.kind == kind }, selectedRow: selectedRow)
        }
    }

    /// 1つの種類の重ね合わせを作ります。
    ///
    /// 責務: その種類の行が1件以上ある時だけ、ID・名前・色の区間・凡例・強調をまとめます。
    /// - Parameters:
    ///   - kind: 規制の種類。
    ///   - rows: その種類の行。
    ///   - selectedRow: 選んでいる行。
    /// - Returns: 重ね合わせ。行が無ければ `nil`。
    private func overlay(
        kind: SessionRoadRegulationReviewKind,
        rows: [SessionRoadRegulationReviewRow],
        selectedRow: SessionRoadRegulationReviewRow?
    ) -> RouteAnalysisOverlay? {
        guard !rows.isEmpty else { return nil }
        return RouteAnalysisOverlay(
            id: keys.overlayID(for: kind),
            titleKey: keys.overlayTitleKey(for: kind),
            runs: runs(rows),
            legend: legend(kind: kind, rows: rows),
            highlightedTimeRanges: highlights(kind: kind, rows: rows, selectedRow: selectedRow)
        )
    }

    /// 色の区間を優先の順に並べます。
    ///
    /// 責務: 分類の優先 → 行の ID の昇順に並べ、各行の連番の範囲と色の分類を区間にします。
    /// - Parameter rows: 1つの種類の行。
    /// - Returns: 色の区間(先が優先)。
    private func runs(_ rows: [SessionRoadRegulationReviewRow]) -> [RouteAnalysisColorRun] {
        rows
            .sorted { (Self.outcomeOrder($0.outcome), $0.id) < (Self.outcomeOrder($1.outcome), $1.id) }
            .map { RouteAnalysisColorRun(sequenceRange: $0.sequenceRange, category: $0.category) }
    }

    /// 凡例を作ります。
    ///
    /// 責務: 現れた分類を優先の順に並べ、最後に「該当する規制なし」を足して 0 から番号を振ります。
    /// - Parameters:
    ///   - kind: 規制の種類。
    ///   - rows: その種類の行。
    /// - Returns: 凡例の項目。
    private func legend(kind: SessionRoadRegulationReviewKind, rows: [SessionRoadRegulationReviewRow]) -> [RouteAnalysisLegendEntry] {
        let outcomes = SessionRoadRegulationReviewOutcome.allCases.filter { outcome in rows.contains { $0.outcome == outcome } }
        let items = outcomes.map { outcome in
            (keys.category(for: outcome), localize(keys.outcomeLabelKey(kind: kind, outcome: outcome)))
        } + [(RouteAnalysisColorCategory.base, localize(keys.notApplicableLabelKey))]
        return items.enumerated().map { index, item in
            RouteAnalysisLegendEntry(id: index, category: item.0, text: item.1)
        }
    }

    /// 強調する時刻の範囲を作ります。
    ///
    /// 責務: 選んだ行がこの種類ならその範囲1つ、それ以外は確認が必要な行の範囲を ID の昇順で返します(どちらも余白つき)。
    /// - Parameters:
    ///   - kind: 規制の種類。
    ///   - rows: その種類の行。
    ///   - selectedRow: 選んでいる行。
    /// - Returns: 強調する時刻の範囲。
    private func highlights(
        kind: SessionRoadRegulationReviewKind,
        rows: [SessionRoadRegulationReviewRow],
        selectedRow: SessionRoadRegulationReviewRow?
    ) -> [ClosedRange<Date>] {
        if let selectedRow, selectedRow.kind == kind {
            return [padded(selectedRow.timeRange)]
        }
        return rows
            .filter { $0.outcome == .possibleIssue }
            .sorted { $0.id < $1.id }
            .map { padded($0.timeRange) }
    }

    /// 範囲の前後に余白を足します。
    ///
    /// 責務: 下限を余白の秒数だけ早め、上限を同じだけ遅らせます。
    /// - Parameter range: 時刻の範囲。
    /// - Returns: 広げた範囲。
    private func padded(_ range: ClosedRange<Date>) -> ClosedRange<Date> {
        range.lowerBound.addingTimeInterval(-highlightPaddingSeconds)...range.upperBound.addingTimeInterval(highlightPaddingSeconds)
    }

    /// 分類の優先の順を返します。
    ///
    /// 責務: 分類の `allCases` の中の位置を返します。
    /// - Parameter outcome: 判定の分類。
    /// - Returns: 0 始まりの位置(小さいほど優先)。
    private static func outcomeOrder(_ outcome: SessionRoadRegulationReviewOutcome) -> Int {
        SessionRoadRegulationReviewOutcome.allCases.firstIndex(of: outcome) ?? SessionRoadRegulationReviewOutcome.allCases.count
    }
}
