#if os(iOS)
import SwiftUI

/// 1台の車両のセッションと合計をまとめた一覧のセクションです。
struct IOSLogVehicleSection: View {
    let group: LogHistoryVehicleGroup
    let send: (LogHistoryAction) -> Void

    var body: some View {
        Section {
            ForEach(group.sessions) { row in
                IOSLogSessionRow(row: row) { send(.detailRequested(row.id)) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("logs.action.delete", role: .destructive) { send(.deleteRequested(row.id)) }
                        if row.canFreeUpSpace {
                            Button("logs.action.freeUp") { send(.freeUpSpaceRequested(row.id)) }
                                .tint(InsightPalette.accent)
                        }
                    }
            }
        } header: {
            VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                if let name = group.vehicleName {
                    Text(verbatim: name).font(InsightTypography.sectionTitle).foregroundStyle(.primary)
                } else {
                    Text("logs.vehicle.unknown").font(InsightTypography.sectionTitle).foregroundStyle(.primary)
                }
                HStack(spacing: InsightSpacing.sm) {
                    Text("logs.group.sessionCount \(group.sessionCount)")
                    Text(verbatim: "·")
                    Text(verbatim: group.totalDurationText)
                    if let distance = group.totalDistanceText {
                        Text(verbatim: "·")
                        Text(verbatim: distance)
                    }
                    if group.interruptedCount > 0 {
                        Text(verbatim: "·")
                        Text("logs.group.interrupted \(group.interruptedCount)")
                            .foregroundStyle(InsightPalette.warning)
                    }
                }
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
            }
            .textCase(nil)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
}
#endif
