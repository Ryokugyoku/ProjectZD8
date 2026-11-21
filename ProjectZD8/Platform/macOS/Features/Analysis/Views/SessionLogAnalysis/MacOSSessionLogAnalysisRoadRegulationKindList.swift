#if os(macOS)
import SwiftUI

/// macOS の「交通規制との照合」のカードで、1種類の規制の見出しと行の並びを描きます。
struct MacOSSessionLogAnalysisRoadRegulationKindList: View {
    /// 表示する1種類の一覧です。
    let section: SessionRoadRegulationReviewSection
    /// 選ばれている行の番号です。無ければ `nil`。
    let selectedRowID: Int?
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 行を選んだことを送出します。
    let onSelectRow: (SessionRoadRegulationReviewRow) -> Void

    /// 見出しと、行(無ければ空の案内)を縦に並べます。
    ///
    /// 責務: 種類名と絞り込み前の件数を見出しにし、行を `LazyVStack` で描くか、行が無い時は空の案内を描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.rowSpacing * metrics.scale) {
            HStack(spacing: MacOSRoadRegulationReviewMetrics.contentSpacing * metrics.scale) {
                Text(LocalizedStringKey(section.titleKey))
                    .font(.system(size: MacOSRoadRegulationReviewMetrics.kindTitleFontSize * metrics.scale, weight: .semibold))
                Text(section.totalCount, format: .number)
                    .font(.system(size: MacOSRoadRegulationReviewMetrics.captionFontSize * metrics.scale))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if let emptyMessageKey = section.emptyMessageKey {
                Text(LocalizedStringKey(emptyMessageKey))
                    .font(.system(size: MacOSRoadRegulationReviewMetrics.captionFontSize * metrics.scale))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.rowSpacing * metrics.scale) {
                    ForEach(section.rows) { row in
                        MacOSSessionLogAnalysisRoadRegulationRow(
                            row: row,
                            isSelected: row.id == selectedRowID,
                            metrics: metrics,
                            onSelect: onSelectRow
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
