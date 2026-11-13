#if os(iOS)
import SwiftUI

/// 車両ごとのPID収集設定です。分類と有効状態で絞り込み、PIDごとに収集を切り替えます。
struct IOSVehiclePIDSettingsView: View {
    let state: VehiclePIDSettingsState
    let failure: VehicleManagementFailure?
    let send: (VehicleManagementAction) -> Void

    var body: some View {
        List {
            if let failure {
                InlineBanner(
                    .error,
                    message: Text(LocalizedStringKey(failure.localizationKey)),
                    action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                categoryFilter
                Picker("garage.pid_settings.enabledFilter", selection: enabledBinding) {
                    ForEach(VehiclePIDEnabledFilter.allCases, id: \.self) { filter in
                        Text(LocalizedStringKey(filter.nameKey)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("garage.pid_settings.summary \(state.enabledCount) \(state.supportedCount) \(state.items.count)")
            }
            Section {
                ForEach(state.visibleItems) { item in
                    IOSVehiclePIDSettingRow(item: item) { isEnabled in
                        send(.pidCollectionToggled(item.request, isEnabled: isEnabled))
                    }
                }
                if state.visibleItems.isEmpty {
                    Text("garage.pid_settings.empty").foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(InsightBackground())
        .navigationTitle(Text("garage.pid_settings.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: InsightSpacing.sm) {
                FilterChip(Text("garage.pid_settings.filter.all"), isSelected: state.categoryFilter == .all) {
                    send(.pidCategoryFilterChanged(.all))
                }
                ForEach(state.availableCategories, id: \.self) { category in
                    FilterChip(Text(LocalizedStringKey(category.nameKey)), isSelected: state.categoryFilter == .category(category)) {
                        send(.pidCategoryFilterChanged(.category(category)))
                    }
                }
                if state.hasVehicleSpecificItems {
                    FilterChip(Text("garage.pid_settings.filter.vehicleSpecific"), isSelected: state.categoryFilter == .vehicleSpecific) {
                        send(.pidCategoryFilterChanged(.vehicleSpecific))
                    }
                }
            }
            .padding(.vertical, InsightSpacing.xs)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: InsightSpacing.lg, bottom: 0, trailing: InsightSpacing.lg))
    }

    private var enabledBinding: Binding<VehiclePIDEnabledFilter> {
        Binding(get: { state.enabledFilter }, set: { send(.pidEnabledFilterChanged($0)) })
    }
}
#endif
