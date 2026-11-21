import Foundation

/// 照合の結果から、一度だけ作る表示の内容(行・まとめ・注記・出典)を組み立てます。
///
/// 部品を順に呼ぶだけで、判定や整形の規則は持ちません。メインの外で呼べます。
nonisolated struct SessionRoadRegulationReviewContentBuilder: Sendable {
    /// 判定を行へ変える部品です。
    private let rowBuilder: SessionRoadRegulationReviewRowBuilder
    /// 行からまとめを作る部品です。
    private let summaryBuilder: SessionRoadRegulationReviewSummaryBuilder
    /// 注記を選ぶ部品です。
    private let noticeBuilder: SessionRoadRegulationReviewNoticeBuilder
    /// 出典の内容を作る部品です。
    private let attributionBuilder: SessionRoadRegulationReviewAttributionBuilder

    /// 内容の各部品を受け取って作ります。
    ///
    /// 責務: 行・まとめ・注記・出典を作る部品を保持します。
    /// - Parameters:
    ///   - rowBuilder: 判定を行へ変える部品。
    ///   - summaryBuilder: 行からまとめを作る部品。
    ///   - noticeBuilder: 注記を選ぶ部品。
    ///   - attributionBuilder: 出典の内容を作る部品。
    init(
        rowBuilder: SessionRoadRegulationReviewRowBuilder = .init(),
        summaryBuilder: SessionRoadRegulationReviewSummaryBuilder = .init(),
        noticeBuilder: SessionRoadRegulationReviewNoticeBuilder = .init(),
        attributionBuilder: SessionRoadRegulationReviewAttributionBuilder = .init()
    ) {
        self.rowBuilder = rowBuilder
        self.summaryBuilder = summaryBuilder
        self.noticeBuilder = noticeBuilder
        self.attributionBuilder = attributionBuilder
    }

    /// 照合の結果から表示の内容を作ります。
    ///
    /// 責務: 判定から行を作り、その行からまとめと注記を、結果から出典を作ってまとめます。
    /// - Parameters:
    ///   - review: 照合の結果。
    ///   - rawLog: 評価に使った Raw の置き場所。
    /// - Returns: 表示の内容。
    func content(for review: SessionRoadRegulationReview, rawLog: SessionRoadRegulationRawLogAvailability) -> SessionRoadRegulationReviewContent {
        let rows = rowBuilder.rows(from: review.entries)
        return SessionRoadRegulationReviewContent(
            rows: rows,
            summaries: summaryBuilder.summaries(for: rows),
            notices: noticeBuilder.notices(review: review, rows: rows, rawLog: rawLog),
            attribution: attributionBuilder.attribution(for: review)
        )
    }
}
