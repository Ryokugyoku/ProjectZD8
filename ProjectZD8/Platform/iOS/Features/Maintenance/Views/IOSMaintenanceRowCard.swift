#if os(iOS)
import SwiftUI

/// 整備記録1件のカードです。実施日・区分・作業項目・写真と締結の件数を示します。
struct IOSMaintenanceRowCard: View {
    let row: MaintenanceListRow
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.sm) {
                    Text(verbatim: row.title)
                        .font(InsightTypography.sectionTitle)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: InsightSpacing.sm)
                    StatusBadge(Text(LocalizedStringKey(row.kindKey)), tone: row.kind == .heavy ? .active : .neutral)
                }
                HStack(spacing: InsightSpacing.sm) {
                    Text(row.performedAt, format: .dateTime.year().month().day())
                    if let odometer = row.odometerText {
                        Text(verbatim: "·")
                        Text(verbatim: odometer)
                    }
                }
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
                ForEach(row.workItems) { item in
                    HStack(spacing: InsightSpacing.xs) {
                        Text(LocalizedStringKey(item.componentKey))
                        Text(verbatim: "·")
                        Text(LocalizedStringKey(item.operationKey))
                        if !item.productName.isEmpty {
                            Text(verbatim: "·")
                            Text(verbatim: item.productName).lineLimit(1)
                        }
                    }
                    .font(InsightTypography.caption)
                    .foregroundStyle(.primary)
                }
                if row.photoCount > 0 || row.fastenerGroupCount > 0 {
                    HStack(spacing: InsightSpacing.md) {
                        if row.photoCount > 0 {
                            Label { Text(row.photoCount, format: .number) } icon: { Image(systemName: "photo") }
                                .accessibilityLabel(Text("maintenance.row.photos \(row.photoCount)"))
                        }
                        if row.fastenerGroupCount > 0 {
                            Label { Text(row.fastenerGroupCount, format: .number) } icon: { Image(systemName: "gearshape.2") }
                                .accessibilityLabel(Text("maintenance.row.fastenerGroups \(row.fastenerGroupCount)"))
                        }
                    }
                    .font(InsightTypography.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(InsightSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: InsightRadius.md, style: .continuous).fill(InsightPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: InsightRadius.md, style: .continuous).strokeBorder(InsightPalette.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("maintenance.action.delete", systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text("maintenance.action.delete"), onDelete)
    }
}
#endif
