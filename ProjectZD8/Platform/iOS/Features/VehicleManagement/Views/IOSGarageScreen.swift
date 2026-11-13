#if os(iOS)
import SwiftUI

/// 登録車両の一覧です。詳細・PID収集設定・整備記録は同じスタックへ push します。
struct IOSGarageScreen: View {
    let vehicles: VehicleManagementState
    let maintenance: MaintenanceState
    let sendVehicle: (VehicleManagementAction) -> Void
    let sendMaintenance: (MaintenanceAction) -> Void

    @State private var path: [IOSGarageRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            list
                .background(InsightBackground())
                .navigationTitle(Text("tab.garage"))
                .navigationDestination(for: IOSGarageRoute.self, destination: destination)
        }
        .refreshable { sendVehicle(.refreshRequested) }
        .sheet(isPresented: vehicleEditorBinding) {
            if let editor = vehicles.editor {
                IOSVehicleEditorView(editor: editor, failure: vehicles.failure, send: sendVehicle)
            }
        }
        .sheet(isPresented: maintenanceEditorBinding) {
            if let editor = maintenance.editor {
                IOSMaintenanceEditorView(editor: editor, failure: maintenance.failure, pendingDeletion: maintenance.pendingDeletion, send: sendMaintenance)
            }
        }
        .confirmationDialog(
            Text("garage.delete.title"),
            isPresented: deletionBinding,
            titleVisibility: .visible,
            presenting: vehicles.pendingDeletion
        ) { _ in
            Button("garage.delete.confirm", role: .destructive) { sendVehicle(.deleteConfirmed) }
            Button("common.cancel", role: .cancel) { sendVehicle(.deleteCancelled) }
        } message: { prompt in
            Text("garage.delete.message \(prompt.vehicleName) \(prompt.sessionCount)")
        }
        .onChange(of: path) { _, newPath in
            if vehicles.pidSettings != nil, !newPath.contains(where: { if case .pidSettings = $0 { true } else { false } }) {
                sendVehicle(.pidSettingsClosed)
            }
        }
        .onChange(of: vehicles.vehicles.map(\.id)) { _, ids in
            path.removeAll { route in
                switch route {
                case .vehicle(let id), .pidSettings(let id), .maintenance(let id): !ids.contains(id)
                }
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if vehicles.vehicles.isEmpty, vehicles.loadPhase == .loaded {
            VStack {
                failureBanner
                EmptyStateView(
                    symbol: "car.side",
                    title: Text("garage.empty.title"),
                    message: Text("garage.empty.message")
                )
            }
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: InsightSpacing.md) {
                    failureBanner
                    ForEach(vehicles.vehicles) { item in
                        NavigationLink(value: IOSGarageRoute.vehicle(item.id)) {
                            IOSVehicleCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: IOSAppShellMetrics.contentMaxWidth)
                .padding(.horizontal, InsightSpacing.screenGutter)
                .padding(.vertical, InsightSpacing.lg)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var failureBanner: some View {
        if let failure = vehicles.failure {
            InlineBanner(
                .error,
                message: Text(LocalizedStringKey(failure.localizationKey)),
                action: InsightAction(Text("common.dismiss")) { sendVehicle(.failureDismissed) }
            )
            .padding(.horizontal, InsightSpacing.screenGutter)
        }
    }

    @ViewBuilder
    private func destination(_ route: IOSGarageRoute) -> some View {
        switch route {
        case .vehicle(let id):
            if let item = vehicles.vehicles.first(where: { $0.id == id }) {
                IOSVehicleDetailView(
                    item: item,
                    failure: vehicles.failure,
                    sendVehicle: sendVehicle,
                    onOpenPIDSettings: {
                        sendVehicle(.pidSettingsRequested(id))
                        path.append(.pidSettings(id))
                    },
                    onOpenMaintenance: {
                        sendMaintenance(.vehicleSelected(id))
                        path.append(.maintenance(id))
                    }
                )
            }
        case .pidSettings:
            if let settings = vehicles.pidSettings {
                IOSVehiclePIDSettingsView(state: settings, failure: vehicles.failure, send: sendVehicle)
            } else {
                ProgressView()
            }
        case .maintenance(let id):
            IOSMaintenanceListView(
                vehicleID: id,
                state: maintenance,
                send: sendMaintenance
            )
        }
    }

    private var vehicleEditorBinding: Binding<Bool> {
        Binding(get: { vehicles.editor != nil }, set: { if !$0 { sendVehicle(.editCancelled) } })
    }

    private var maintenanceEditorBinding: Binding<Bool> {
        Binding(get: { maintenance.editor != nil }, set: { if !$0 { sendMaintenance(.editCancelled) } })
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { vehicles.pendingDeletion != nil }, set: { if !$0 { sendVehicle(.deleteCancelled) } })
    }
}
#endif
