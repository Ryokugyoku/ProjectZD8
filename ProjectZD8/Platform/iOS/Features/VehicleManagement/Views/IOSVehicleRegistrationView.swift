#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// iPhoneでOBD識別確認と未登録車両の入力を行います。
struct IOSVehicleRegistrationView: View {
    /// Applicationが公開する現在の車両管理状態です。
    let state: VehicleManagementState
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void

    /// 現在段階に対応するiPhone専用の登録導線を提供します。
    ///
    /// 責務: OBD識別状態を待機、確認、入力、失敗のいずれかへ描画します。
    var body: some View {
        NavigationStack {
            Group {
                switch state.phase {
                case .identifying, .loading:
                    ProgressView("garage.status.identifying")
                        .controlSize(.large)
                case .confirmingIdentification:
                    if let snapshot = state.pendingIdentification { confirmation(snapshot) }
                case .registering, .editing:
                    if let vehicle = state.editingVehicle {
                        IOSVehicleEditorView(vehicle: vehicle, send: send)
                    }
                case .failed:
                    ContentUnavailableView {
                        Label("garage.error.title", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(LocalizedStringKey(state.failureKey ?? "garage.error.obd_unavailable"))
                    } actions: {
                        Button("garage.retry") { send(.identificationRetryRequested) }
                        Button("garage.cancel") { send(.registrationCancelled) }
                    }
                default:
                    ContentUnavailableView("garage.ready.title", systemImage: "checkmark.circle.fill")
                }
            }
            .navigationTitle("garage.registration.navigation")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("ios-vehicle-registration")
    }

    /// VINまたは非VIN識別子と全取得情報を登録前の確認一覧として表示します。
    ///
    /// 責務: 1回のOBD識別観測を確認または取消できるiPhone画面へ変換します。
    /// - Parameter snapshot: 確認対象の識別観測。
    /// - Returns: 車両識別子、全観測フィールド、確認操作を含む表示。
    private func confirmation(_ snapshot: VehicleIdentificationSnapshot) -> some View {
        List {
            Section(snapshot.vin == nil ? "garage.field.obd_identifier" : "garage.identification.vin") {
                Text(snapshot.vin ?? snapshot.obdIdentifier ?? "—")
                    .font(.system(.body, design: .monospaced, weight: .bold))
                    .textSelection(.enabled)
            }
            Section("garage.identification.all_fields") {
                ForEach(snapshot.fields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label).font(.headline)
                        Text(field.value).textSelection(.enabled)
                        Text(field.source).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
            Section {
                Button("garage.identification.confirm") { send(.identificationConfirmed) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("garage.cancel", role: .cancel) { send(.registrationCancelled) }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("garage.identification.description")
            }
        }
    }
}
#endif
