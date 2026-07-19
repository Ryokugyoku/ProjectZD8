#if os(iOS)
import SwiftUI

/// iPhoneで登録車両とPID収集設定導線を表示します。
struct IOSGarageView: View {
    /// Applicationが公開する車両管理状態です。
    let state: VehicleManagementState
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void

    /// 登録車両ごとの編集とPID設定を提供します。
    ///
    /// 責務: 登録車両一覧をiPhone用の車両設定操作へ変換します。
    var body: some View {
        NavigationStack {
            List(state.vehicles) { vehicle in
                VStack(alignment: .leading, spacing: 8) {
                    Text(vehicle.name.isEmpty ? vehicle.displayIdentifier : vehicle.name).font(.headline)
                    Text(vehicle.displayIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                    HStack {
                        Button("garage.edit") { send(.editRequested(vehicle.id)) }
                        Button("garage.pid_settings.open") { send(.pidSettingsRequested(vehicle.id)) }
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("garage.title")
            .overlay {
                if state.vehicles.isEmpty { ContentUnavailableView("garage.empty.title", systemImage: "car.side") }
            }
        }
        .sheet(isPresented: Binding(
            get: { state.pidSettingsVehicleID != nil },
            set: { if !$0 { send(.pidSettingsClosed) } }
        )) {
            IOSVehiclePIDSettingsView(items: state.pidSelectionItems, send: send)
        }
    }
}
#endif
