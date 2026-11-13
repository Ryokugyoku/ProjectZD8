#if os(iOS)
import SwiftUI

/// 1台の車両の詳細です。属性・活動の要約と、編集・PID収集設定・整備・削除への入口を持ちます。
struct IOSVehicleDetailView: View {
    let item: VehicleListItem
    let failure: VehicleManagementFailure?
    let sendVehicle: (VehicleManagementAction) -> Void
    let onOpenPIDSettings: () -> Void
    let onOpenMaintenance: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InsightSpacing.lg) {
                if let failure {
                    InlineBanner(
                        .error,
                        message: Text(LocalizedStringKey(failure.localizationKey)),
                        action: InsightAction(Text("common.dismiss")) { sendVehicle(.failureDismissed) }
                    )
                }
                header
                profileCard
                activityCard
                entries
            }
            .frame(maxWidth: IOSAppShellMetrics.contentMaxWidth)
            .padding(.horizontal, InsightSpacing.screenGutter)
            .padding(.vertical, InsightSpacing.lg)
            .frame(maxWidth: .infinity)
        }
        .background(InsightBackground())
        .navigationTitle(Text(verbatim: item.vehicle.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sendVehicle(.editRequested(item.id)) } label: { Text("garage.detail.edit") }
            }
        }
    }

    private var header: some View {
        HStack(spacing: InsightSpacing.lg) {
            VehicleAvatar(imageData: item.photoData, name: item.vehicle.name, size: IOSAppShellMetrics.vehicleDetailAvatarSize)
            VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                Text(verbatim: item.vehicle.name).font(InsightTypography.screenTitle)
                if item.activity.isRecording {
                    StatusBadge(Text("drive.phase.recording"), tone: .active, symbol: "record.circle")
                }
            }
        }
    }

    private var profileCard: some View {
        let vehicle = item.vehicle
        return InsightCard(title: Text("garage.detail.profile")) {
            KeyValueRow(Text("garage.detail.identifier"), value: vehicle.displayIdentifier.isEmpty ? Text("common.unavailable") : Text(verbatim: vehicle.displayIdentifier))
            if !vehicle.manufacturer.isEmpty {
                KeyValueRow(Text("garage.field.manufacturer"), value: Text(verbatim: vehicle.manufacturer))
            }
            if !vehicle.engineModel.isEmpty {
                KeyValueRow(Text("garage.field.engineModel"), value: Text(verbatim: vehicle.engineModel))
            }
            if let year = vehicle.modelYear {
                KeyValueRow(Text("garage.field.modelYear"), value: Text(verbatim: String(year)), isNumeric: true)
            }
            KeyValueRow(Text("garage.field.powertrain"), value: Text(LocalizedStringKey(item.powertrainNameKey)))
            KeyValueRow(Text("garage.field.energySources"), value: energySourcesText)
            if let tank = vehicle.tankCapacityLiters {
                KeyValueRow(Text("garage.field.tankCapacity"), value: Text(Measurement(value: tank, unit: UnitVolume.liters), format: .measurement(width: .abbreviated)), isNumeric: true)
            }
            if !vehicle.note.isEmpty {
                VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                    Text("garage.field.note").font(InsightTypography.caption).foregroundStyle(.secondary)
                    Text(verbatim: vehicle.note).font(InsightTypography.body)
                }
            }
        }
    }

    /// エネルギー源を読点でつないだ表示です。無ければ欠損です。
    private var energySourcesText: Text {
        let names = item.energySourceNameKeys.map { Text(LocalizedStringKey($0)) }
        guard let first = names.first else { return Text("common.unavailable") }
        return names.dropFirst().reduce(first) { $0 + Text(verbatim: ", ") + $1 }
    }

    private var activityCard: some View {
        let activity = item.activity
        return InsightCard(title: Text("garage.detail.activity")) {
            KeyValueRow(Text("garage.detail.sessions"), value: Text(activity.sessionCount, format: .number), isNumeric: true)
            KeyValueRow(Text("garage.detail.totalDuration"), value: Text(verbatim: activity.totalRecordedDurationText), isNumeric: true)
            KeyValueRow(
                Text("garage.detail.lastLogged"),
                value: activity.lastLoggedAt.map { Text($0, format: .dateTime.year().month().day().hour().minute()) } ?? Text("common.unavailable")
            )
            KeyValueRow(
                Text("garage.detail.odometer"),
                value: activity.latestOdometerText.map { Text(verbatim: $0) } ?? Text("common.unavailable"),
                isNumeric: true
            )
            if activity.interruptedCount > 0 {
                KeyValueRow(Text("garage.detail.interrupted"), value: Text(activity.interruptedCount, format: .number), isNumeric: true)
            }
        }
    }

    private var entries: some View {
        VStack(spacing: InsightSpacing.md) {
            entry("garage.detail.pidSettings", symbol: "slider.horizontal.3", action: onOpenPIDSettings)
            entry("garage.detail.maintenance", symbol: "wrench.and.screwdriver", action: onOpenMaintenance)
            Button { sendVehicle(.deleteRequested(item.id)) } label: {
                Label("garage.detail.delete", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.insightDestructive)
        }
    }

    private func entry(_ key: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: InsightSpacing.md) {
                Image(systemName: symbol).foregroundStyle(InsightPalette.accent).frame(width: InsightSpacing.xl)
                Text(key).font(InsightTypography.body).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(InsightSpacing.lg)
            .frame(minHeight: InsightSpacing.minimumHitTarget)
            .background(RoundedRectangle(cornerRadius: InsightRadius.md, style: .continuous).fill(InsightPalette.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
