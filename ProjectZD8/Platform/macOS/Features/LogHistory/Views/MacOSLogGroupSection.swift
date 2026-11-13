#if os(macOS)
import SwiftUI

/// 車両ごとのセッション群(見出しに件数・累積時間・累積距離)。
struct MacOSLogGroupSection: View {
    let group: LogHistoryVehicleGroup
    let selectedID: SessionID?
    let onSelect: (SessionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.sm) {
            InsightSectionHeader(
                group.vehicleName.map { Text(verbatim: $0) } ?? Text("history.group.unknownVehicle"),
                subtitle: subtitle
            ) {
                if group.interruptedCount > 0 {
                    StatusBadge(Text("history.group.interrupted \(group.interruptedCount)"), tone: .warning)
                }
            }
            ForEach(group.sessions) { row in
                MacOSLogSessionRow(row: row, isSelected: row.id == selectedID) { onSelect(row.id) }
            }
        }
    }

    private var subtitle: Text {
        var parts = [group.totalDurationText]
        if let distance = group.totalDistanceText { parts.append(distance) }
        return Text("history.group.summary \(group.sessionCount) \(parts.joined(separator: " · "))")
    }
}
#endif
