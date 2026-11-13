#if os(iOS)
import SwiftUI

/// 車両一覧の1枚のカードです。写真(またはモノグラム)・名前・識別子・活動の要約を示します。
struct IOSVehicleCard: View {
    let item: VehicleListItem

    var body: some View {
        HStack(alignment: .top, spacing: InsightSpacing.md) {
            VehicleAvatar(imageData: item.photoData, name: item.vehicle.name, size: IOSAppShellMetrics.vehicleCardAvatarSize)
            VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.sm) {
                    Text(verbatim: item.vehicle.name)
                        .font(InsightTypography.sectionTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: InsightSpacing.sm)
                    if item.activity.isRecording {
                        StatusBadge(Text("drive.phase.recording"), tone: .active, symbol: "record.circle")
                    }
                }
                if !item.vehicle.displayIdentifier.isEmpty {
                    Text(verbatim: item.vehicle.displayIdentifier)
                        .font(InsightTypography.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(LocalizedStringKey(item.powertrainNameKey))
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
                activityLine
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(InsightSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: InsightRadius.md, style: .continuous).fill(InsightPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: InsightRadius.md, style: .continuous).strokeBorder(InsightPalette.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var activityLine: some View {
        let activity = item.activity
        if activity.sessionCount == 0 {
            Text("garage.card.noLogs")
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: InsightSpacing.sm) {
                Text("garage.card.sessions \(activity.sessionCount)")
                Text(verbatim: "·")
                Text(verbatim: activity.totalRecordedDurationText)
                if let last = activity.lastLoggedAt {
                    Text(verbatim: "·")
                    Text(last, format: .dateTime.month().day())
                }
                if activity.interruptedCount > 0 {
                    Text(verbatim: "·")
                    Text("garage.card.interrupted \(activity.interruptedCount)")
                        .foregroundStyle(InsightPalette.warning)
                }
            }
            .font(InsightTypography.caption)
            .foregroundStyle(.secondary)
        }
    }
}
#endif
