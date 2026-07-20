#if os(iOS)
import SwiftUI

/// iPhoneで登録車両とPID収集設定導線を表示します。
struct IOSGarageView: View {
    /// 削除確認中の車両です。
    @State private var deletionCandidate: VehicleProfile? = nil
    /// Applicationが公開する車両管理状態です。
    let state: VehicleManagementState
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void

    /// 登録車両の現状または選択した車両の編集画面を提示します。
    ///
    /// 責務: 車両管理状態を編集フォームまたはカード型一覧へ変換して型付き操作へ接続します。
    @ViewBuilder
    var body: some View {
        if let vehicle = state.editingVehicle,
           state.phase == .registering || state.phase == .editing {
            NavigationStack {
                IOSVehicleEditorView(vehicle: vehicle, send: send)
            }
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        titleSection
                        statusSection

                        if state.vehicles.isEmpty, state.phase == .loading {
                            ProgressView("garage.status.loading")
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .padding(.horizontal, 18)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        } else if state.vehicles.isEmpty {
                            ContentUnavailableView("garage.empty.title", systemImage: "car.side")
                                .frame(maxWidth: .infinity, minHeight: 220)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(
                                        colors: [Color.accentColor.opacity(0.08), Color.black.opacity(0.03)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                                )
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(state.vehicles) { vehicle in
                                    vehicleCard(vehicle)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("garage.title")
                .navigationBarTitleDisplayMode(.large)
                .background {
                    LinearGradient(
                        colors: [Color.primary.opacity(0.05), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ).ignoresSafeArea()
                }
                .onAppear { send(.refreshRequested) }
                .accessibilityIdentifier("ios-garage-screen")
            }
            .sheet(isPresented: Binding(
                get: { state.pidSettingsVehicleID != nil },
                set: { if !$0 { send(.pidSettingsClosed) } }
            )) {
                IOSVehiclePIDSettingsView(items: state.pidSelectionItems, send: send)
            }
            .alert(
                "garage.delete.title",
                isPresented: Binding(
                    get: { deletionCandidate != nil },
                    set: { if !$0 { deletionCandidate = nil } }
                ),
                presenting: deletionCandidate
            ) { vehicle in
                Button("garage.delete.action", role: .destructive) {
                    deletionCandidate = nil
                    send(.vehicleDeleted(vehicle.id))
                }
                Button("garage.cancel", role: .cancel) { deletionCandidate = nil }
            } message: { _ in
                Text("garage.delete.message")
            }
        }
    }

    /// Garageの冒頭導線を車両仕様に沿って整えます。
    ///
    /// 責務: 1画面の主目的と補助文言を結びつけたヘッダーを描画します。
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("garage.eyebrow")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(.secondary)

            Text("garage.title")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("garage.subtitle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 接続状態、同期状態、識別エラーを短く提示します。
    ///
    /// 責務: 接続対象、同期待ち、同期失敗を1カードに集約して状態更新を明確化します。
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let failureKey = state.failureKey {
                Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline.weight(.semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            } else if state.phase == .readyToConnect, let vehicle = state.connectionVehicle {
                Label("garage.ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.bold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        Text(vehicle.displayIdentifier)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 10)
                            .padding(.top, 8)
                    }
            } else if state.hasLoadedVehicles {
                Label("garage.synced", systemImage: "icloud.and.arrow.down")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .font(.system(.footnote, design: .rounded))
    }

    /// 車両1件分を画像＋編集・同期ボタンで提示します。
    ///
    /// 責務: 1台の登録車両をタップ可能なカードとして編集導線と削除操作へ変換します。
    /// - Parameter vehicle: 描画対象の登録車両。
    /// - Returns: 写真、識別情報、主要操作を持つカード。
    private func vehicleCard(_ vehicle: VehicleProfile) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            vehicleImage(vehicle)
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150)
                .clipped()

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Text(vehicle.name.isEmpty ? vehicle.displayIdentifier : vehicle.name)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    if vehicle.isDefault {
                        Text("garage.default")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.16), in: Capsule())
                    }
                }
                Text(vehicle.manufacturer.isEmpty ? "garage.unknown_manufacturer" : vehicle.manufacturer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(vehicle.displayIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                Button("garage.edit") { send(.editRequested(vehicle.id)) }
                    .buttonStyle(.borderedProminent)
                Button("garage.pid_settings.open") { send(.pidSettingsRequested(vehicle.id)) }
                    .buttonStyle(.bordered)
                Button(role: .destructive) { deletionCandidate = vehicle } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("garage.delete.action")
                .accessibilityIdentifier("ios-garage-delete-\(vehicle.id.rawValue.uuidString)")
                Spacer()
            }
            .font(.system(.callout, design: .rounded))
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 6)
    }

    /// 画像なしでも崩れないプロフィール画像表示を生成します。
    ///
    /// 責務: プロフィール画像が未設定時に統一ルックの代替ビジュアルを返します。
    /// - Parameter vehicle: 表示対象車両。
    /// - Returns: 実画像 or ブランド背景を持つ占位画像。
    @ViewBuilder
    private func vehicleImage(_ vehicle: VehicleProfile) -> some View {
        if let data = vehicle.photoData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [.accentColor.opacity(0.56), .black.opacity(0.74)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
#endif
