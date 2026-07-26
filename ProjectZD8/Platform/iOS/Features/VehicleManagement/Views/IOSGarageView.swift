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
                        fleetSummary

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
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("garage.eyebrow")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(.tint)
                Text("garage.title")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("garage.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { send(.refreshRequested) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("garage.refresh")
        }
    }

    /// 登録台数と蓄積セッション数をGarageの概要として表示します。
    ///
    /// 責務: 車両管理状態の全体量を2件の即読可能な集計へ変換します。
    private var fleetSummary: some View {
        HStack(spacing: 12) {
            summaryTile(value: "\(state.vehicles.count)", key: "garage.summary.vehicles", symbol: "car.2.fill")
            summaryTile(
                value: "\(state.activityByVehicleID.values.reduce(0) { $0 + $1.sessionCount })",
                key: "garage.summary.sessions",
                symbol: "waveform.path.ecg"
            )
        }
    }

    /// 1件のGarage全体集計を小型カードへ変換します。
    ///
    /// 責務: 単一の集計値をアイコン、値、ラベルを持つ概要カードとして描画します。
    /// - Parameters:
    ///   - value: 強調表示する集計値。
    ///   - key: 集計内容を説明するローカライズキー。
    ///   - symbol: 集計内容を補助するSF Symbol名。
    /// - Returns: Garage概要用の小型カード。
    private func summaryTile(value: String, key: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(.title3, design: .rounded, weight: .bold))
                Text(key).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            } else if state.phase == .identifying {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small).tint(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("garage.connection.in_progress").font(.headline)
                        Text("garage.identification.loading_hint").font(.caption).opacity(0.82)
                    }
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            } else if state.phase == .readyToConnect, let vehicle = state.connectionVehicle {
                Label("garage.connection.handoff", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
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
        let activity = state.activityByVehicleID[vehicle.id] ?? VehicleActivitySummary()
        return VStack(alignment: .leading, spacing: 13) {
            ZStack(alignment: .topLeading) {
                vehicleImage(vehicle)
                    .frame(maxWidth: .infinity, minHeight: 176, maxHeight: 176)
                    .clipped()
                if activity.isConnected {
                    Label("garage.connection.active", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.9), in: Capsule())
                        .padding(12)
                }
                if let modelCode = state.specialPIDModelCodeByVehicleID[vehicle.id] {
                    VehicleModelBadge(modelCode: modelCode)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(vehicle.name.isEmpty ? vehicle.displayIdentifier : vehicle.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(vehicle.manufacturer.isEmpty ? "garage.unknown_manufacturer" : vehicle.manufacturer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(vehicle.displayIdentifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Divider().opacity(0.6)
            HStack(spacing: 0) {
                activityMetric(value: "\(activity.sessionCount)", key: "garage.activity.sessions", symbol: "rectangle.stack.fill")
                Divider().frame(height: 34)
                activityMetric(value: durationText(activity.totalRecordedDuration), key: "garage.activity.duration", symbol: "clock.fill")
            }

            if let odometer = activity.latestOdometerKilometers {
                HStack(spacing: 7) {
                    Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(.tint)
                    Text("garage.activity.odometer").foregroundStyle(.secondary)
                    Spacer()
                    Text(odometer, format: .number.precision(.fractionLength(0...1)))
                        .fontWeight(.semibold)
                    Text("km").foregroundStyle(.secondary)
                    if let modelCode = activity.odometerModelCode {
                        VehicleModelBadge(modelCode: modelCode)
                            .scaleEffect(0.72)
                            .frame(width: 30, height: 30)
                    }
                }
                .font(.caption)
            }

            HStack(spacing: 7) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.tint)
                Text("garage.activity.last_log")
                    .foregroundStyle(.secondary)
                Spacer()
                if let date = activity.lastLoggedAt {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .fontWeight(.semibold)
                } else {
                    Text("garage.activity.no_logs").fontWeight(.semibold)
                }
            }
            .font(.caption)

            HStack(spacing: 10) {
                Button { send(.editRequested(vehicle.id)) } label: {
                    Label("garage.edit", systemImage: "slider.horizontal.3")
                }.buttonStyle(.borderedProminent)
                Button { send(.pidSettingsRequested(vehicle.id)) } label: {
                    Label("garage.pid_settings.open", systemImage: "waveform.badge.magnifyingglass")
                }.buttonStyle(.bordered)
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
        .accessibilityIdentifier("ios-garage-vehicle-\(vehicle.id.rawValue.uuidString)")
    }

    /// 車両カード内の単一アクティビティ集計を表示します。
    ///
    /// 責務: 1件の車両別集計値を均等幅の指標表示へ変換します。
    /// - Parameters:
    ///   - value: 表示する集計値。
    ///   - key: 集計内容のローカライズキー。
    ///   - symbol: 集計内容を補助するSF Symbol名。
    /// - Returns: 車両カード用の指標表示。
    private func activityMetric(value: String, key: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(.headline, design: .rounded, weight: .bold))
                Text(key).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    /// 記録秒数を短い時分表記へ変換します。
    ///
    /// 責務: 車両別の累積記録時間をカード幅に収まる単一文字列へ変換します。
    /// - Parameter duration: 非負として表示する累積秒数。
    /// - Returns: 時間または分単位の短い表示文字列。
    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration) / 60)
        return totalMinutes >= 60 ? "\(totalMinutes / 60)h \(totalMinutes % 60)m" : "\(totalMinutes)m"
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
