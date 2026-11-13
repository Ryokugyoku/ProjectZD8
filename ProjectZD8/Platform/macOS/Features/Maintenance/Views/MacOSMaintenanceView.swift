#if os(macOS)
import SwiftUI

/// 整備画面。車両選択・種別フィルタ・記録タイムライン・エディタ・削除確認。
struct MacOSMaintenanceView: View {
    let state: MaintenanceState
    let send: (MaintenanceAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InsightSpacing.lg) {
                if let failure = state.failure {
                    InlineBanner(
                        .error,
                        message: Text(LocalizedStringKey(failure.localizationKey)),
                        action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                    )
                }
                content
            }
            .padding(MacOSAppShellMetrics.contentPadding)
            .frame(maxWidth: MacOSAppShellMetrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(InsightBackground())
        .navigationTitle(Text("shell.destination.maintenance"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(MaintenanceKind.allCases, id: \.self) { kind in
                        Button {
                            send(.createRequested(kind))
                        } label: {
                            Text(LocalizedStringKey(kind.localizationKey))
                        }
                    }
                } label: {
                    Label("maintenance.action.new", systemImage: "plus")
                }
                .disabled(state.selectedVehicleID == nil)
            }
        }
        .sheet(isPresented: Binding(
            get: { state.editor != nil },
            set: { if !$0, state.editor != nil { send(.editCancelled) } }
        )) {
            if let editor = state.editor {
                MacOSMaintenanceEditorSheet(editor: editor, send: send)
            }
        }
        .confirmationDialog(
            Text("maintenance.delete.title"),
            isPresented: Binding(
                get: { state.pendingDeletion != nil },
                set: { if !$0, state.pendingDeletion != nil { send(.deleteCancelled) } }
            ),
            titleVisibility: .visible,
            presenting: state.pendingDeletion
        ) { _ in
            Button(role: .destructive) {
                send(.deleteConfirmed)
            } label: {
                Text("maintenance.delete.confirm")
            }
            Button(role: .cancel) {
                send(.deleteCancelled)
            } label: {
                Text("common.cancel")
            }
        } message: { prompt in
            Text("maintenance.delete.message \(prompt.title) \(prompt.photoCount)")
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.loadPhase != .loaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        } else if state.vehicles.isEmpty {
            EmptyStateView(
                symbol: "wrench.and.screwdriver",
                title: Text("maintenance.empty.noVehicle.title"),
                message: Text("maintenance.empty.noVehicle.message")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            controls
            if state.rows.isEmpty {
                EmptyStateView(
                    symbol: "wrench.and.screwdriver",
                    title: Text("maintenance.empty.title"),
                    message: Text("maintenance.empty.message")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else if state.visibleRows.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: Text("maintenance.filtered_empty.title"),
                    action: InsightAction(Text("maintenance.filter.all")) { send(.kindFilterChanged(nil)) }
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVStack(alignment: .leading, spacing: InsightSpacing.md) {
                    ForEach(state.visibleRows) { row in
                        MacOSMaintenanceRowView(row: row, send: send)
                    }
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: InsightSpacing.md) {
            Picker(selection: Binding(
                get: { state.selectedVehicleID },
                set: { if let id = $0 { send(.vehicleSelected(id)) } }
            )) {
                ForEach(state.vehicles) { vehicle in
                    Text(verbatim: vehicle.name).tag(Optional(vehicle.id))
                }
            } label: {
                Text("maintenance.vehicle")
            }
            .fixedSize()

            FilterChip(Text("maintenance.filter.all"), isSelected: state.kindFilter == nil) {
                send(.kindFilterChanged(nil))
            }
            ForEach(MaintenanceKind.allCases, id: \.self) { kind in
                FilterChip(Text(LocalizedStringKey(kind.localizationKey)), isSelected: state.kindFilter == kind) {
                    send(.kindFilterChanged(kind))
                }
            }
            Spacer()
            Text("maintenance.counts \(state.lightCount) \(state.heavyCount)")
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
