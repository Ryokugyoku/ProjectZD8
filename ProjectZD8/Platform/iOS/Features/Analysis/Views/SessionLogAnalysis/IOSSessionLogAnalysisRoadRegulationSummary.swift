#if os(iOS)
import SwiftUI

/// iPhone の解析の「交通規制との照合」で、規制の種類ごとの通過の件数と結果の内訳を2列のタイルで並べます。
struct IOSSessionLogAnalysisRoadRegulationSummary: View {
    /// 種類ごとのまとめ(表示順)です。
    let summaries: [SessionRoadRegulationReviewKindSummary]

    /// 見出しとタイルの格子を描画します。
    ///
    /// 責務: 「まとめ」の見出しの下に、種類ごとのタイルを決まった列の数で並べます。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.summaryTileSpacing) {
            Text("analysis.road_regulation.summary.title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.summaryTileSpacing) {
                ForEach(summaries) { summary in
                    tile(summary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 同じ幅の列を決まった数だけ並べる格子の列です。
    private var columns: [GridItem] {
        let item = GridItem(.flexible(), spacing: IOSRoadRegulationReviewMetrics.summaryTileSpacing, alignment: .top)
        return Array(repeating: item, count: IOSRoadRegulationReviewMetrics.summaryColumns)
    }

    /// 1種類のタイルを作ります。
    ///
    /// 責務: 種類名と通過の件数(0件は「通過なし」)を置き、件数が1以上の結果だけを色見本・ラベル・件数で並べます。
    /// - Parameter summary: 1種類のまとめ。
    /// - Returns: タイルの View。
    private func tile(_ summary: SessionRoadRegulationReviewKindSummary) -> some View {
        VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.summaryTileSpacing) {
            Text(LocalizedStringKey(summary.titleKey))
                .font(.subheadline.weight(.semibold))
            passedLine(total: summary.total)
            ForEach(summary.counts) { count in
                countLine(count)
            }
        }
        .padding(IOSRoadRegulationReviewMetrics.summaryTilePadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Color.primary.opacity(IOSRoadRegulationReviewMetrics.tileBackgroundOpacity),
            in: RoundedRectangle(cornerRadius: IOSRoadRegulationReviewMetrics.summaryTileCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    /// 通過の件数の行を作ります。
    ///
    /// 責務: 件数が0なら「通過なし」、1以上なら「通過」と件数を描きます。
    /// - Parameter total: その種類の通過の件数。
    /// - Returns: 件数の行の View。
    @ViewBuilder private func passedLine(total: Int) -> some View {
        if total == 0 {
            Text("analysis.road_regulation.summary.none")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: IOSRoadRegulationReviewMetrics.rowSpacing) {
                Text("analysis.road_regulation.summary.passed")
                Text(total, format: .number).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// 1つの結果の件数の行を作ります。
    ///
    /// 責務: 結果の色見本・ラベル・件数を横に並べます。
    /// - Parameter count: 結果ごとの件数。
    /// - Returns: 件数の行の View。
    private func countLine(_ count: SessionRoadRegulationReviewCount) -> some View {
        HStack(spacing: IOSRoadRegulationReviewMetrics.rowSpacing) {
            Circle()
                .fill(count.category.color)
                .frame(width: IOSRoadRegulationReviewMetrics.swatchSize, height: IOSRoadRegulationReviewMetrics.swatchSize)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(count.labelKey))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(count.count, format: .number).monospacedDigit()
        }
        .font(.caption)
    }
}
#endif
