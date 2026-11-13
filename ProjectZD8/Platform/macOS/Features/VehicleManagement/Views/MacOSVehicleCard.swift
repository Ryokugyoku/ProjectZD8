#if os(macOS)
import SwiftUI

/// ガレージの車両カード(写真 / モノグラム・名前・識別子・活動サマリー・記録中バッジ)。
struct MacOSVehicleCard: View {
    let item: VehicleListItem
    let send: (VehicleManagementAction) -> Void

    var body: some View {
        InsightCard {
            VStack(alignment: .leading, spacing: InsightSpacing.md) {
                HStack(alignment: .top, spacing: InsightSpacing.md) {
                    VehicleAvatar(imageData: item.photoData, name: item.vehicle.name, size: 64)
                    VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                        Text(verbatim: item.vehicle.name)
                            .font(InsightTypography.sectionTitle)
                            .lineLimit(2)
                        if let subtitle {
                            Text(verbatim: subtitle).font(InsightTypography.caption).foregroundStyle(.secondary)
                        }
                        Text(verbatim: item.vehicle.displayIdentifier)
                            .font(InsightTypography.numeric(.caption))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    if item.activity.isRecording {
                        StatusBadge(Text("garage.badge.recording"), tone: .critical, symbol: "record.circle")
                    }
                }

                HStack(spacing: InsightSpacing.sm) {
                    StatusBadge(Text(LocalizedStringKey(item.powertrainNameKey)), tone: .neutral)
                    ForEach(item.energySourceNameKeys, id: \.self) { key in
                        StatusBadge(Text(LocalizedStringKey(key)), tone: .neutral)
                    }
                }

                Divider()
                activity

                HStack {
                    Button {
                        send(.editRequested(item.id))
                    } label: {
                        Label("garage.action.edit", systemImage: "pencil")
                    }
                    Button {
                        send(.pidSettingsRequested(item.id))
                    } label: {
                        Label("garage.action.pidSettings", systemImage: "slider.horizontal.3")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        send(.deleteRequested(item.id))
                    } label: {
                        Label("garage.action.delete", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(item.activity.isRecording)
                    .help(Text("garage.action.delete"))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String? {
        let parts = [item.vehicle.manufacturer, item.vehicle.engineModel, item.vehicle.modelYear.map { String($0) } ?? ""]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var activity: some View {
        if item.activity.sessionCount == 0 {
            Text("garage.activity.no_logs").font(InsightTypography.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: InsightSpacing.xs) {
                KeyValueRow(Text("garage.activity.sessions"), value: Text(verbatim: item.activity.sessionCount.formatted()), isNumeric: true)
                KeyValueRow(Text("garage.activity.duration"), value: Text(verbatim: item.activity.totalRecordedDurationText), isNumeric: true)
                KeyValueRow(
                    Text("garage.activity.last_log"),
                    value: item.activity.lastLoggedAt.map { Text($0, format: .dateTime.year().month().day()) } ?? Text(verbatim: "—")
                )
                KeyValueRow(
                    Text("garage.activity.odometer"),
                    value: Text(verbatim: item.activity.latestOdometerText ?? "—"),
                    isNumeric: true
                )
                if item.activity.interruptedCount > 0 {
                    KeyValueRow(Text("garage.activity.interrupted"), value: Text(verbatim: item.activity.interruptedCount.formatted()), isNumeric: true)
                }
            }
        }
    }
}
#endif
