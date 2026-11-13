#if os(macOS)
import SwiftUI

/// ガレージ画面。車両カードの適応グリッドと、編集・PID 設定・削除確認。
struct MacOSGarageView: View {
    let state: VehicleManagementState
    let send: (VehicleManagementAction) -> Void

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
        .navigationTitle(Text("shell.destination.garage"))
        .sheet(isPresented: Binding(
            get: { state.editor != nil },
            set: { if !$0, state.editor != nil { send(.editCancelled) } }
        )) {
            if let editor = state.editor {
                MacOSVehicleEditorSheet(editor: editor, send: send)
            }
        }
        .sheet(isPresented: Binding(
            get: { state.pidSettings != nil },
            set: { if !$0, state.pidSettings != nil { send(.pidSettingsClosed) } }
        )) {
            if let settings = state.pidSettings {
                MacOSVehiclePIDSettingsSheet(settings: settings, send: send)
            }
        }
        .confirmationDialog(
            Text("garage.delete.title"),
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
                Text("garage.delete.confirm")
            }
            Button(role: .cancel) {
                send(.deleteCancelled)
            } label: {
                Text("common.cancel")
            }
        } message: { prompt in
            Text("garage.delete.message \(prompt.vehicleName) \(prompt.sessionCount)")
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.loadPhase != .loaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        } else if state.vehicles.isEmpty {
            EmptyStateView(
                symbol: "car.2",
                title: Text("garage.empty.title"),
                message: Text("garage.empty.message")
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 340, maximum: 460), spacing: InsightSpacing.lg, alignment: .top)],
                alignment: .leading,
                spacing: InsightSpacing.lg
            ) {
                ForEach(state.vehicles) { item in
                    MacOSVehicleCard(item: item, send: send)
                }
            }
        }
    }
}
#endif
