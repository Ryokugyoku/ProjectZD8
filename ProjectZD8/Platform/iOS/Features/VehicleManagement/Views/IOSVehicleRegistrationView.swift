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
                    VStack(spacing: 16) {
                        ProgressView("garage.status.identifying")
                            .controlSize(.large)
                        Text("garage.identification.loading_hint")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .background(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.11), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 22)
                    )
                    .padding(.horizontal)
                case .confirmingIdentification:
                    if let snapshot = state.pendingIdentification { confirmation(snapshot) }
                case .registering, .editing:
                    if let vehicle = state.editingVehicle {
                        IOSVehicleEditorView(vehicle: vehicle, send: send)
                    }
                case .failed:
                    VStack(spacing: 16) {
                        Label("garage.error.title", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(LocalizedStringKey(state.failureKey ?? "garage.error.obd_unavailable"))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("garage.retry") { send(.identificationRetryRequested) }
                                .buttonStyle(.borderedProminent)
                            Button("garage.cancel") { send(.registrationCancelled) }
                                .buttonStyle(.bordered)
                        }
                    }
                case .idle, .readyToConnect:
                    EmptyView()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("garage.identification.eyebrow", systemImage: "car.badge.gearshape")
                    .foregroundStyle(.tint)
                Text(snapshot.vin == nil ? "garage.field.obd_identifier" : "garage.identification.vin")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(snapshot.vin ?? snapshot.obdIdentifier ?? "—")
                    .font(.system(.title3, design: .monospaced, weight: .bold))
                    .textSelection(.enabled)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(snapshot.fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label)
                                .font(.headline)
                            Text(field.value).textSelection(.enabled)
                            Text(field.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 12) {
                    Button("garage.identification.confirm") { send(.identificationConfirmed) }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    Button("garage.cancel", role: .cancel) { send(.registrationCancelled) }
                        .frame(maxWidth: .infinity)
                }
                Text("garage.identification.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }
}
#endif
