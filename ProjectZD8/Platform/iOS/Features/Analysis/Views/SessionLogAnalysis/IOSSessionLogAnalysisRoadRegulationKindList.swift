#if os(iOS)
import SwiftUI

/// iPhone の解析の「交通規制との照合」で、規制の1種類の見出しと、その種類の行の並びを描画します。
struct IOSSessionLogAnalysisRoadRegulationKindList: View {
    /// 1種類の一覧(絞り込み後の行)です。
    let section: SessionRoadRegulationReviewSection
    /// 選ばれている行の番号です。選択が無ければ `nil`。
    let selectedRowID: Int?
    /// 行の選択を送出します。
    let onSelect: (SessionRoadRegulationReviewRow) -> Void

    /// 見出しと行の並び、または行が無い時の案内を描画します。
    ///
    /// 責務: 種類名と絞り込み前の件数を見出しにし、行があれば行を、無ければ状態が決めた案内の文言を置きます。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.rowSpacing) {
            header
            if let emptyMessageKey = section.emptyMessageKey {
                Text(LocalizedStringKey(emptyMessageKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LazyVStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.rowSpacing) {
                ForEach(section.rows) { row in
                    IOSSessionLogAnalysisRoadRegulationRow(row: row, isSelected: row.id == selectedRowID) { onSelect(row) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 種類名と件数の見出しです。
    private var header: some View {
        HStack(spacing: IOSRoadRegulationReviewMetrics.rowSpacing) {
            Text(LocalizedStringKey(section.titleKey))
                .font(.headline)
            Text(section.totalCount, format: .number)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
#endif
