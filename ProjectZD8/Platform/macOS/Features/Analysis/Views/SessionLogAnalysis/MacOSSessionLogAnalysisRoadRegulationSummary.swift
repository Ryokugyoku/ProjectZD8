#if os(macOS)
import SwiftUI

/// macOS の「交通規制との照合」のカードで、種類ごとの通過件数と結果の内訳を4列のタイルで並べます。
struct MacOSSessionLogAnalysisRoadRegulationSummary: View {
    /// 種類ごとのまとめ(表示順)です。
    let summaries: [SessionRoadRegulationReviewKindSummary]
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 見出しの下に、種類ごとのタイルを格子に並べます。
    ///
    /// 責務: まとめの見出しと、種類ごとのタイルを描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
            Text("analysis.road_regulation.summary.title")
                .font(.system(size: MacOSRoadRegulationReviewMetrics.kindTitleFontSize * metrics.scale, weight: .semibold))
            LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                ForEach(summaries) { summary in
                    tile(summary)
                }
            }
        }
    }

    /// タイルどうしの間隔(倍率を掛けた値)です。
    private var spacing: CGFloat {
        MacOSRoadRegulationReviewMetrics.summaryTileSpacing * metrics.scale
    }

    /// 同じ幅の4列です。
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
            count: MacOSRoadRegulationReviewMetrics.summaryColumns
        )
    }

    /// 1種類のタイルを作ります。
    ///
    /// 責務: 種類名と通過件数、件数のある結果の内訳(無ければ「通過なし」)を縦に並べ、角丸の背景で囲みます。
    /// - Parameter summary: 1種類のまとめ。
    /// - Returns: タイルの View。
    private func tile(_ summary: SessionRoadRegulationReviewKindSummary) -> some View {
        VStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
            Text(LocalizedStringKey(summary.titleKey))
                .font(.system(size: MacOSRoadRegulationReviewMetrics.kindTitleFontSize * metrics.scale, weight: .semibold))
            HStack(spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
                Text("analysis.road_regulation.summary.passed")
                Text(summary.total, format: .number)
                    .monospacedDigit()
            }
            .font(.system(size: MacOSRoadRegulationReviewMetrics.captionFontSize * metrics.scale))
            .foregroundStyle(.secondary)
            if summary.counts.isEmpty {
                Text("analysis.road_regulation.summary.none")
                    .font(.system(size: MacOSRoadRegulationReviewMetrics.captionFontSize * metrics.scale))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.counts) { count in
                    countLine(count)
                }
            }
        }
        .padding(MacOSRoadRegulationReviewMetrics.summaryTilePadding * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tileShape.fill(Color.primary.opacity(MacOSRoadRegulationReviewMetrics.fillOpacity)))
        .overlay {
            tileShape.stroke(
                Color.primary.opacity(MacOSRoadRegulationReviewMetrics.borderOpacity),
                lineWidth: MacOSRoadRegulationReviewMetrics.borderWidth * metrics.scale
            )
        }
        .accessibilityElement(children: .combine)
    }

    /// タイルの角丸の形です。
    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacOSRoadRegulationReviewMetrics.summaryTileCornerRadius * metrics.scale, style: .continuous)
    }

    /// 結果1つの「色見本 + ラベル + 件数」を作ります。
    ///
    /// 責務: 結果の色の丸、結果のラベル、件数を横に並べます。
    /// - Parameter count: 結果ごとの件数。
    /// - Returns: 1行の View。
    private func countLine(_ count: SessionRoadRegulationReviewCount) -> some View {
        HStack(spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
            Circle()
                .fill(count.category.color)
                .frame(
                    width: MacOSRoadRegulationReviewMetrics.swatchSize * metrics.scale,
                    height: MacOSRoadRegulationReviewMetrics.swatchSize * metrics.scale
                )
                .accessibilityHidden(true)
            Text(LocalizedStringKey(count.labelKey))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(count.count, format: .number)
                .monospacedDigit()
        }
        .font(.system(size: MacOSRoadRegulationReviewMetrics.captionFontSize * metrics.scale))
    }
}
#endif
