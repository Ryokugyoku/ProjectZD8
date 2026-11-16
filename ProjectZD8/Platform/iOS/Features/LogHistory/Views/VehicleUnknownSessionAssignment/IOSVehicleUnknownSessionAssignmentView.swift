#if os(iOS)
import SwiftUI

/// 車両を特定できなかったログを選び、登録済みの車両へ紐付ける iOS の画面です。
struct IOSVehicleUnknownSessionAssignmentView: View {
    /// 紐付け画面の状態です。
    let state: VehicleUnknownSessionAssignmentState
    /// 候補の登録済み車両です。
    let vehicles: [VehicleProfile]
    /// 操作を通知するクロージャです。
    let send: (VehicleUnknownSessionAction) -> Void

    /// ログの一覧・車両の一覧・失敗の表示と、閉じる・紐付けの操作を提供します。
    ///
    /// 責務: 部品を配置し、選択と紐付けと閉じる操作を型付き操作として通知します。
    var body: some View {
        NavigationStack {
            List {
                sessionsSection
                vehiclesSection
                if let failureKey = state.failureKey {
                    Text(LocalizedStringKey(failureKey)).foregroundStyle(.orange)
                }
            }
            .navigationTitle(Text("vehicle_unknown.assignment.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("vehicle_unknown.assignment.close") { send(.assignmentDismissed) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("vehicle_unknown.assignment.assign") { send(.assignRequested(vehicles: vehicles)) }
                        .disabled(!state.canAssign(among: vehicles))
                }
            }
        }
        .accessibilityIdentifier("ios-vehicle-unknown-session-assignment")
    }

    /// 紐付けるログを選ぶ区画です。
    private var sessionsSection: some View {
        Section("vehicle_unknown.assignment.sessions.header") {
            ForEach(state.sessions) { session in
                IOSVehicleUnknownSessionAssignmentSessionRow(
                    session: session,
                    isSelected: state.isSelected(session.id),
                    toggle: { send(.sessionSelectionToggled(session.id)) }
                )
            }
        }
    }

    /// 紐付け先の車両を選ぶ区画です。
    private var vehiclesSection: some View {
        Section("vehicle_unknown.assignment.vehicles.header") {
            if let messageKey = state.noVehicleMessageKey(among: vehicles) {
                Text(LocalizedStringKey(messageKey)).foregroundStyle(.secondary)
            }
            ForEach(vehicles) { vehicle in
                IOSVehicleUnknownSessionAssignmentVehicleRow(
                    vehicle: vehicle,
                    isSelected: state.selectedVehicleID == vehicle.id,
                    select: { send(.vehicleSelected(vehicle.id)) }
                )
            }
        }
    }
}
#endif
