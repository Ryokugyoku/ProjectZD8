import Foundation

/// 照合の判定を、表示の順に並べた一覧の行へ変えます。
///
/// 並べ方は、開始の観測時刻の昇順 → 種類(`SessionRoadRegulationReviewKind.allCases` の順)→ 入力の順(安定)です。
/// 行の `id` は並べた後の位置(0 始まり)です。
nonisolated struct SessionRoadRegulationReviewRowBuilder: Sendable {
    /// 時刻と数値の文字列を作る部品です。
    private let formatter: SessionRoadRegulationReviewRowFormatter
    /// キー・記号・色の分類の表引きです。
    private let keys: SessionRoadRegulationReviewTextKeys

    /// 文字列の部品と表引きを受け取って作ります。
    ///
    /// 責務: 行の文字列と表引きに使う部品を保持します。
    /// - Parameters:
    ///   - formatter: 時刻と数値の文字列を作る部品。
    ///   - keys: キー・記号・色の分類の表引き。
    init(formatter: SessionRoadRegulationReviewRowFormatter = .init(), keys: SessionRoadRegulationReviewTextKeys = .init()) {
        self.formatter = formatter
        self.keys = keys
    }

    /// 判定を並べて行にします。
    ///
    /// 責務: 判定を表示の順に並べ、位置を `id` にして行へ写します。
    /// - Parameter entries: 照合の判定(並びは問いません)。
    /// - Returns: 並べた行(入力が空なら空)。
    func rows(from entries: [SessionRoadRegulationReviewEntry]) -> [SessionRoadRegulationReviewRow] {
        let ordered = entries.enumerated().sorted { Self.precedes($0, $1) }.map(\.element)
        return ordered.enumerated().map { index, entry in row(id: index, entry: entry) }
    }

    /// 1件の判定を行にします。
    ///
    /// 責務: 開始と終了の印の小さい方から大きい方を範囲にし、キー・記号・色・文字列を添えます。
    /// - Parameters:
    ///   - id: 並べた後の位置。
    ///   - entry: 判定。
    /// - Returns: 一覧の行。
    private func row(id: Int, entry: SessionRoadRegulationReviewEntry) -> SessionRoadRegulationReviewRow {
        let lowerDate = min(entry.start.observedAt, entry.end.observedAt)
        let upperDate = max(entry.start.observedAt, entry.end.observedAt)
        let timeRange = lowerDate...upperDate
        let sequenceRange = min(entry.start.sequence, entry.end.sequence)...max(entry.start.sequence, entry.end.sequence)
        return SessionRoadRegulationReviewRow(
            id: id,
            kind: entry.kind,
            outcome: entry.outcome,
            category: keys.category(for: entry.outcome),
            titleKey: entry.verdictKey,
            systemImage: keys.systemImage(for: entry.outcome),
            timeText: formatter.timeText(timeRange),
            figureTexts: formatter.figureTexts(entry.figures, kind: entry.kind),
            timeRange: timeRange,
            sequenceRange: sequenceRange,
            undeterminedReason: entry.undeterminedReason,
            overlayID: keys.overlayID(for: entry.kind)
        )
    }

    /// 2件の判定の前後を決めます。
    ///
    /// 責務: 開始の観測時刻、種類の順、入力の位置の順で比べます。
    /// - Parameters:
    ///   - lhs: 入力の位置と判定。
    ///   - rhs: 入力の位置と判定。
    /// - Returns: `lhs` が先なら `true`。
    private static func precedes(
        _ lhs: (offset: Int, element: SessionRoadRegulationReviewEntry),
        _ rhs: (offset: Int, element: SessionRoadRegulationReviewEntry)
    ) -> Bool {
        let left = (lhs.element.start.observedAt, kindOrder(lhs.element.kind), lhs.offset)
        let right = (rhs.element.start.observedAt, kindOrder(rhs.element.kind), rhs.offset)
        return left < right
    }

    /// 種類の表示の順を返します。
    ///
    /// 責務: 種類の `allCases` の中の位置を返します。
    /// - Parameter kind: 規制の種類。
    /// - Returns: 0 始まりの位置。
    private static func kindOrder(_ kind: SessionRoadRegulationReviewKind) -> Int {
        SessionRoadRegulationReviewKind.allCases.firstIndex(of: kind) ?? SessionRoadRegulationReviewKind.allCases.count
    }
}
