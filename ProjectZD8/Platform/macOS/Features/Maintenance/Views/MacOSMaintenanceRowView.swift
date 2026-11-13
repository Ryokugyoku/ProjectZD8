#if os(macOS)
import SwiftUI

/// 整備タイムラインの1件(種別・タイトル・日付・走行距離・作業内容の要約)。
struct MacOSMaintenanceRowView: View {
    let row: MaintenanceListRow
    let send: (MaintenanceAction) -> Void

    var body: some View {
        InsightCard {
            VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.sm) {
                    Text(verbatim: row.title).font(InsightTypography.sectionTitle)
                    StatusBadge(Text(LocalizedStringKey(row.kindKey)), tone: row.kind == .heavy ? .warning : .active)
                    Spacer()
                    Text(row.performedAt, format: .dateTime.year().month().day())
                        .font(InsightTypography.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: InsightSpacing.md) {
                    if let odometer = row.odometerText { Label(odometer, systemImage: "gauge.with.needle") }
                    if row.photoCount > 0 {
                        Label {
                            Text("maintenance.row.photos \(row.photoCount)")
                        } icon: {
                            Image(systemName: "photo")
                        }
                    }
                    if row.fastenerGroupCount > 0 {
                        Label {
                            Text("maintenance.row.fasteners \(row.fastenerGroupCount)")
                        } icon: {
                            Image(systemName: "wrench.adjustable")
                        }
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
                            Text(verbatim: "—")
                            Text(verbatim: item.productName).foregroundStyle(.secondary)
                        }
                    }
                    .font(InsightTypography.body)
                }
                if !row.notes.isEmpty {
                    Text(verbatim: row.notes)
                        .font(InsightTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                HStack {
                    Button {
                        send(.editRequested(row.id))
                    } label: {
                        Label("maintenance.action.edit", systemImage: "pencil")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        send(.deleteRequested(row.id))
                    } label: {
                        Label("maintenance.action.delete", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .help(Text("maintenance.action.delete"))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
#endif
