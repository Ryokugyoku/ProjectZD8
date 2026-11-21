#if os(iOS)
import SwiftUI

/// iPhone の解析の「交通規制との照合」の一覧の1行です。判定の文言・時刻・数値を示し、選ぶとその区間を地図とグラフで示します。
struct IOSSessionLogAnalysisRoadRegulationRow: View {
    /// 表示する行です。
    let row: SessionRoadRegulationReviewRow
    /// この行が選ばれている時に `true` です。
    let isSelected: Bool
    /// この行の選択を送出します。
    let onSelect: () -> Void

    /// 行をボタンとして描画します。
    ///
    /// 責務: 色見本と記号・判定の文言・時刻と数値を並べ、選ばれている行は枠をシアンにします。
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: IOSRoadRegulationReviewMetrics.rowSpacing) {
                marker
                VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.rowSpacing) {
                    Text(LocalizedStringKey(row.titleKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    details
                }
                Spacer(minLength: 0)
            }
            .padding(IOSRoadRegulationReviewMetrics.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(IOSRoadRegulationReviewMetrics.tileBackgroundOpacity), in: shape)
            .overlay { shape.stroke(borderColor, lineWidth: borderWidth) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("analysis.road_regulation.row.show_on_map"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("ios-analysis-road-regulation-row-\(row.id)")
    }

    /// 行の枠の形です。
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: IOSRoadRegulationReviewMetrics.rowCornerRadius, style: .continuous)
    }

    /// 枠の色です。選ばれている行はアクセントのシアンにします。
    private var borderColor: Color {
        isSelected ? .cyan : Color.primary.opacity(IOSRoadRegulationReviewMetrics.rowBorderOpacity)
    }

    /// 枠の太さです。選ばれている行は太くします。
    private var borderWidth: CGFloat {
        isSelected ? IOSRoadRegulationReviewMetrics.selectedBorderWidth : IOSRoadRegulationReviewMetrics.rowBorderWidth
    }

    /// 結果の色見本と記号です。
    ///
    /// 責務: 結果の色の丸と、結果の記号を同じ色で横に並べます。
    private var marker: some View {
        HStack(spacing: IOSRoadRegulationReviewMetrics.rowSpacing) {
            Circle()
                .fill(row.category.color)
                .frame(width: IOSRoadRegulationReviewMetrics.swatchSize, height: IOSRoadRegulationReviewMetrics.swatchSize)
            Image(systemName: row.systemImage)
                .font(.subheadline)
                .foregroundStyle(row.category.color)
        }
        .accessibilityHidden(true)
    }

    /// 時刻と数値の行です。
    ///
    /// 責務: 幅が足りれば時刻と数値を1行に、足りなければ時刻の下に数値を並べます(文字の結合はしません)。
    private var details: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: IOSRoadRegulationReviewMetrics.rowPadding) {
                timeText
                figures
            }
            VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.rowSpacing / 2) {
                timeText
                figures
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// 区間の時刻の文字です。
    private var timeText: some View {
        Text(verbatim: row.timeText).monospacedDigit()
    }

    /// 解決済みの数値の文字を横に並べます。
    private var figures: some View {
        HStack(spacing: IOSRoadRegulationReviewMetrics.rowPadding) {
            ForEach(Array(row.figureTexts.enumerated()), id: \.offset) { _, text in
                Text(verbatim: text).monospacedDigit()
            }
        }
    }
}
#endif
