#if os(macOS)
import SwiftUI

/// 車両ごとの PID 収集設定シート(カテゴリ・有効状態の絞り込みと PID ごとのトグル)。
struct MacOSVehiclePIDSettingsSheet: View {
    let settings: VehiclePIDSettingsState
    let send: (VehicleManagementAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                    Text("garage.pid_settings.title").font(InsightTypography.screenTitle)
                    Text(verbatim: settings.vehicleName).font(InsightTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("garage.pid_settings.counts \(settings.enabledCount) \(settings.supportedCount)")
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
            }

            filters

            List(settings.visibleItems) { item in
                row(item)
            }
            .listStyle(.inset)
            .overlay {
                if settings.visibleItems.isEmpty {
                    EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: Text("garage.pid_settings.empty"))
                }
            }

            HStack {
                Spacer()
                Button {
                    send(.pidSettingsClosed)
                } label: {
                    Text("common.done")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(InsightSpacing.xl)
        .frame(width: MacOSAppShellMetrics.editorSheetWidth)
        .frame(minHeight: MacOSAppShellMetrics.editorSheetMinHeight + 60)
    }

    private var filters: some View {
        HStack(spacing: InsightSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: InsightSpacing.sm) {
                    FilterChip(Text("garage.pid_settings.filter.all"), isSelected: settings.categoryFilter == .all) {
                        send(.pidCategoryFilterChanged(.all))
                    }
                    ForEach(settings.availableCategories, id: \.self) { category in
                        FilterChip(Text(LocalizedStringKey(category.nameKey)), isSelected: settings.categoryFilter == .category(category)) {
                            send(.pidCategoryFilterChanged(.category(category)))
                        }
                    }
                    if settings.hasVehicleSpecificItems {
                        FilterChip(Text("garage.pid_settings.vehicleSpecific"), isSelected: settings.categoryFilter == .vehicleSpecific) {
                            send(.pidCategoryFilterChanged(.vehicleSpecific))
                        }
                    }
                }
            }
            Picker(selection: Binding(
                get: { settings.enabledFilter },
                set: { send(.pidEnabledFilterChanged($0)) }
            )) {
                ForEach(VehiclePIDEnabledFilter.allCases, id: \.self) { filter in
                    Text(LocalizedStringKey(filter.nameKey)).tag(filter)
                }
            } label: {
                Text("garage.pid_settings.filter.title")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func row(_ item: VehiclePIDSettingItem) -> some View {
        HStack(spacing: InsightSpacing.md) {
            VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
                HStack(spacing: InsightSpacing.sm) {
                    Text(LocalizedStringKey(item.nameKey))
                    if item.isVehicleSpecific { StatusBadge(Text("garage.pid_settings.vehicleSpecificBadge"), tone: .active) }
                }
                HStack(spacing: InsightSpacing.sm) {
                    if let category = item.category {
                        Text(LocalizedStringKey(category.nameKey))
                    }
                    if !item.unit.isEmpty { Text(verbatim: item.unit) }
                    Text(LocalizedStringKey(supportKey(item.support)))
                }
                .font(InsightTypography.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: Binding(
                get: { item.isEnabled },
                set: { send(.pidCollectionToggled(item.request, isEnabled: $0)) }
            )) {
                Text(LocalizedStringKey(item.nameKey))
            }
            .labelsHidden()
            .disabled(!item.isSupported)
        }
        .padding(.vertical, InsightSpacing.xxs)
        .opacity(item.isSupported ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    private func supportKey(_ support: PIDSupport) -> String {
        "garage.pid_settings.support.\(support.rawValue)"
    }
}
#endif
