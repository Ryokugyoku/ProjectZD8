#if os(macOS)
import SwiftUI

/// macOSで複数車両のカード、OBD識別確認、編集導線を描画します。
struct MacOSGarageView: View {
    /// Applicationが公開する車両管理状態です。
    let state: VehicleManagementState
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// Garageの現在段階に対応するmacOS専用レイアウトを提供します。
    ///
    /// 責務: 車両管理状態を一覧、識別確認、編集のいずれかへ描画します。
    var body: some View {
        Group {
            if state.phase == .confirmingIdentification, let snapshot = state.pendingIdentification {
                identificationConfirmation(snapshot)
            } else if let vehicle = state.editingVehicle,
                      state.phase == .registering || state.phase == .editing {
                MacOSVehicleEditorView(vehicle: vehicle, send: send, metrics: metrics)
            } else {
                garageCatalog
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("macos-garage-screen")
    }

    /// 登録車両カードと同期操作を表示するカタログです。
    private var garageCatalog: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6 * metrics.scale) {
                        Text("garage.eyebrow")
                            .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                            .tracking(1.7 * metrics.scale)
                            .foregroundStyle(.tint)
                        Text("garage.title")
                            .font(.system(size: 32 * metrics.scale, weight: .bold, design: .rounded))
                        Text("garage.subtitle")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { send(.refreshRequested) } label: {
                        Label("garage.refresh", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)
                }

                statusBanner

                if state.vehicles.isEmpty, state.phase != .loading {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 270 * metrics.scale), spacing: 18 * metrics.scale)],
                        spacing: 18 * metrics.scale
                    ) {
                        ForEach(state.vehicles) { vehicle in
                            vehicleCard(vehicle)
                        }
                    }
                }
            }
            .padding(32 * metrics.scale)
            .frame(maxWidth: 1_180 * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// 読込、失敗、接続準備状態を一覧上部へ表示します。
    @ViewBuilder
    private var statusBanner: some View {
        if state.phase == .loading || state.phase == .identifying {
            Label("garage.status.loading", systemImage: "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
        } else if let failureKey = state.failureKey {
            Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(14 * metrics.scale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14 * metrics.scale))
        } else if state.connectionVehicle != nil, state.phase == .readyToConnect {
            Label("garage.ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    /// 車両未登録時にHOME接続からの登録手順を説明します。
    private var emptyState: some View {
        ContentUnavailableView(
            "garage.empty.title",
            systemImage: "car.badge.gearshape",
            description: Text("garage.empty.description")
        )
        .frame(maxWidth: .infinity, minHeight: 300 * metrics.scale)
    }

    /// 1台分の写真、主要諸元、編集操作をカードへまとめます。
    ///
    /// 責務: 1件の車両プロフィールを選択可能なGarageカードとして描画します。
    /// - Parameter vehicle: 描画対象の登録車両。
    /// - Returns: 写真と編集・削除操作を持つカード。
    private func vehicleCard(_ vehicle: VehicleProfile) -> some View {
        VStack(alignment: .leading, spacing: 15 * metrics.scale) {
            ZStack(alignment: .topTrailing) {
                vehicleImage(vehicle)
                    .frame(maxWidth: .infinity, minHeight: 145 * metrics.scale, maxHeight: 145 * metrics.scale)
                    .clipped()
                if vehicle.isDefault {
                    Text("garage.default")
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 6 * metrics.scale) {
                Text(vehicle.name.isEmpty ? vehicle.displayIdentifier : vehicle.name)
                    .font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))
                Text(vehicle.manufacturer.isEmpty ? "garage.unknown_manufacturer" : vehicle.manufacturer)
                    .foregroundStyle(.secondary)
                Text(vehicle.displayIdentifier)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            HStack {
                Button("garage.edit") { send(.editRequested(vehicle.id)) }
                    .buttonStyle(.borderedProminent)
                Button(role: .destructive) { send(.vehicleDeleted(vehicle.id)) } label: {
                    Image(systemName: "trash")
                }
                Spacer()
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("garage.synced"))
            }
        }
        .padding(14 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24 * metrics.scale).stroke(Color.primary.opacity(0.08)) }
    }

    /// 車両写真または写真未設定のコンセプト背景を表示します。
    ///
    /// 責務: 1件のプロフィール画像データをカード用ビジュアルへ変換します。
    /// - Parameter vehicle: 写真を保持する車両プロフィール。
    /// - Returns: 写真または代替シンボル。
    @ViewBuilder
    private func vehicleImage(_ vehicle: VehicleProfile) -> some View {
        if let data = vehicle.photoData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [.accentColor.opacity(0.42), .black.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 52 * metrics.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    /// 未登録のVINまたは非VIN識別子と全取得情報をユーザー確認用に表示します。
    ///
    /// 責務: 1回のOBD識別観測を登録可否の確認画面として描画します。
    /// - Parameter snapshot: 確認対象の改変しないOBD観測。
    /// - Returns: 全フィールドと確認操作を持つ画面。
    private func identificationConfirmation(_ snapshot: VehicleIdentificationSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22 * metrics.scale) {
                Label("garage.identification.eyebrow", systemImage: "car.badge.gearshape")
                    .foregroundStyle(.tint)
                Text("garage.identification.title")
                    .font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))
                Text("garage.identification.description")
                    .foregroundStyle(.secondary)
                Text(snapshot.vin ?? snapshot.obdIdentifier ?? "—")
                    .font(.system(size: 24 * metrics.scale, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    ForEach(snapshot.fields) { field in
                        GridRow {
                            Text(field.label).foregroundStyle(.secondary)
                            Text(field.value).textSelection(.enabled)
                            Text(field.source).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))

                HStack {
                    Button("garage.cancel") { send(.registrationCancelled) }
                    Button("garage.identification.confirm") { send(.identificationConfirmed) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(36 * metrics.scale)
            .frame(maxWidth: 900 * metrics.scale, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}
#endif
