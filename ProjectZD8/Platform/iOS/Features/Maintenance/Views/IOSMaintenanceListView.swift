#if os(iOS)
import SwiftUI

/// 1台の車両の整備記録を時系列で示す画面です。区分で絞り込み、新規作成・編集・削除へ進めます。
struct IOSMaintenanceListView: View {
    let vehicleID: VehicleID
    let state: MaintenanceState
    let send: (MaintenanceAction) -> Void

    var body: some View {
        Group {
            if state.selectedVehicleID != vehicleID || state.loadPhase != .loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .background(InsightBackground())
        .navigationTitle(Text("maintenance.list.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(MaintenanceKind.allCases, id: \.self) { kind in
                        Button { send(.createRequested(kind)) } label: {
                            Text(LocalizedStringKey(kind.localizationKey))
                        }
                    }
                } label: {
                    Label("maintenance.list.add", systemImage: "plus")
                }
            }
        }
        .confirmationDialog(
            Text("maintenance.delete.title"),
            isPresented: Binding(
                get: { state.pendingDeletion != nil && state.editor == nil },
                set: { if !$0 { send(.deleteCancelled) } }
            ),
            titleVisibility: .visible,
            presenting: state.pendingDeletion
        ) { _ in
            Button("maintenance.delete.confirm", role: .destructive) { send(.deleteConfirmed) }
            Button("common.cancel", role: .cancel) { send(.deleteCancelled) }
        } message: { prompt in
            Text("maintenance.delete.message \(prompt.title) \(prompt.photoCount)")
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: InsightSpacing.md) {
                if let failure = state.failure, state.editor == nil {
                    InlineBanner(
                        .error,
                        message: Text(LocalizedStringKey(failure.localizationKey)),
                        action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                    )
                }
                filterBar
                if state.visibleRows.isEmpty {
                    EmptyStateView(
                        symbol: "wrench.and.screwdriver",
                        title: Text(state.rows.isEmpty ? "maintenance.empty.title" : "maintenance.filteredEmpty.title"),
                        message: Text(state.rows.isEmpty ? "maintenance.empty.message" : "maintenance.filteredEmpty.message")
                    )
                } else {
                    ForEach(state.visibleRows) { row in
                        IOSMaintenanceRowCard(row: row, onOpen: { send(.editRequested(row.id)) }, onDelete: { send(.deleteRequested(row.id)) })
                    }
                }
            }
            .frame(maxWidth: IOSAppShellMetrics.contentMaxWidth)
            .padding(.horizontal, InsightSpacing.screenGutter)
            .padding(.vertical, InsightSpacing.lg)
            .frame(maxWidth: .infinity)
        }
    }

    private var filterBar: some View {
        HStack(spacing: InsightSpacing.sm) {
            FilterChip(Text("maintenance.filter.all \(state.rows.count)"), isSelected: state.kindFilter == nil) {
                send(.kindFilterChanged(nil))
            }
            FilterChip(Text("maintenance.filter.light \(state.lightCount)"), isSelected: state.kindFilter == .light) {
                send(.kindFilterChanged(.light))
            }
            FilterChip(Text("maintenance.filter.heavy \(state.heavyCount)"), isSelected: state.kindFilter == .heavy) {
                send(.kindFilterChanged(.heavy))
            }
        }
    }
}
#endif
