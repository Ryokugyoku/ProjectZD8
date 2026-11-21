#if os(macOS)
import SwiftUI

/// macOS の「交通規制との照合」の一覧の1行です。選ぶと、その区間を地図とグラフで示す操作を送出します。
struct MacOSSessionLogAnalysisRoadRegulationRow: View {
    /// 表示する行です。
    let row: SessionRoadRegulationReviewRow
    /// この行が選ばれている時に `true` です。
    let isSelected: Bool
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 行を選んだことを送出します。
    let onSelect: (SessionRoadRegulationReviewRow) -> Void

    /// 色見本・アイコン・判定の文言・時刻と数値を1つのボタンとして描画します。
    ///
    /// 責務: 行の値をそのまま描き、押されたら行を送出し、選ばれている時は枠をシアンにします。
    var body: some View {
        Button { onSelect(row) } label: {
            HStack(alignment: .top, spacing: MacOSRoadRegulationReviewMetrics.rowPadding * metrics.scale) {
                marker
                VStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale / 2) {
                    Text(LocalizedStringKey(row.titleKey))
                        .font(.system(size: MacOSRoadRegulationReviewMetrics.rowTitleFontSize * metrics.scale, weight: .medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    details
                }
                Spacer(minLength: 0)
            }
            .padding(MacOSRoadRegulationReviewMetrics.rowPadding * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowShape.fill(Color.primary.opacity(MacOSRoadRegulationReviewMetrics.fillOpacity)))
            .overlay { rowShape.stroke(borderColor, lineWidth: borderWidth) }
            .contentShape(rowShape)
        }
        .buttonStyle(.plain)
        .help("analysis.road_regulation.row.show_on_map")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("macos-analysis-road-regulation-row-\(row.id)")
    }

    /// 結果の色の丸とアイコンです。
    private var marker: some View {
        HStack(spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
            Circle()
                .fill(row.category.color)
                .frame(
                    width: MacOSRoadRegulationReviewMetrics.swatchSize * metrics.scale,
                    height: MacOSRoadRegulationReviewMetrics.swatchSize * metrics.scale
                )
            Image(systemName: row.systemImage)
                .font(.system(size: MacOSRoadRegulationReviewMetrics.rowIconFontSize * metrics.scale, weight: .semibold))
                .foregroundStyle(row.category.color)
        }
        .accessibilityHidden(true)
    }

    /// 時刻と数値の文字を横に並べます。
    private var details: some View {
        HStack(spacing: MacOSRoadRegulationReviewMetrics.rowPadding * metrics.scale) {
            Text(verbatim: row.timeText)
                .monospacedDigit()
            ForEach(Array(row.figureTexts.enumerated()), id: \.offset) { _, text in
                Text(verbatim: text)
                    .monospacedDigit()
            }
        }
        .font(.system(size: MacOSRoadRegulationReviewMetrics.captionFontSize * metrics.scale))
        .foregroundStyle(.secondary)
    }

    /// 行の角丸の形です。
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacOSRoadRegulationReviewMetrics.rowCornerRadius * metrics.scale, style: .continuous)
    }

    /// 枠線の色です。選ばれている時はアクセントのシアンにします。
    private var borderColor: Color {
        isSelected ? Color.cyan : Color.primary.opacity(MacOSRoadRegulationReviewMetrics.borderOpacity)
    }

    /// 枠線の太さ(倍率を掛けた値)です。選ばれている時は太くします。
    private var borderWidth: CGFloat {
        let width = isSelected ? MacOSRoadRegulationReviewMetrics.selectedBorderWidth : MacOSRoadRegulationReviewMetrics.borderWidth
        return width * metrics.scale
    }
}
#endif
