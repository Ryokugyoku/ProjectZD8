#if os(macOS)
import SwiftUI

/// macOSで複数車両のカード、OBD識別確認、編集導線を描画します。
struct MacOSGarageView: View {
    /// 削除確認中の車両です。
    @State private var deletionCandidate: VehicleProfile? = nil
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
        .onAppear { send(.refreshRequested) }
        .sheet(isPresented: Binding(
            get: { state.pidSettingsVehicleID != nil },
            set: { if !$0 { send(.pidSettingsClosed) } }
        )) {
            MacOSVehiclePIDSettingsView(items: state.pidSelectionItems, send: send)
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
                    .buttonStyle(.bordered)
                }

                statusBanner
                fleetSummary

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

    /// Garage全体の登録台数と接続履歴量を横並びで表示します。
    ///
    /// 責務: 車両管理状態をmacOS向けの即読可能な全体集計へ変換します。
    private var fleetSummary: some View {
        HStack(spacing: 12 * metrics.scale) {
            summaryTile(value: "\(state.vehicles.count)", key: "garage.summary.vehicles", symbol: "car.2.fill")
            summaryTile(
                value: "\(state.activityByVehicleID.values.reduce(0) { $0 + $1.sessionCount })",
                key: "garage.summary.sessions",
                symbol: "waveform.path.ecg"
            )
            summaryTile(
                value: "\(state.activityByVehicleID.values.filter(\.isConnected).count)",
                key: "garage.summary.connected",
                symbol: "antenna.radiowaves.left.and.right"
            )
        }
    }

    /// 1件の全体集計をmacOS用の小型カードへ変換します。
    ///
    /// 責務: 単一の集計値をアイコン、値、説明を持つ概要カードとして描画します。
    /// - Parameters:
    ///   - value: 強調表示する集計値。
    ///   - key: 集計内容を説明するローカライズキー。
    ///   - symbol: 集計内容を補助するSF Symbol名。
    /// - Returns: macOS Garage用の概要カード。
    private func summaryTile(value: String, key: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 12 * metrics.scale) {
            Image(systemName: symbol)
                .font(.system(size: 18 * metrics.scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 38 * metrics.scale, height: 38 * metrics.scale)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 11 * metrics.scale))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 21 * metrics.scale, weight: .bold, design: .rounded))
                Text(key).font(.system(size: 11 * metrics.scale)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(13 * metrics.scale)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17 * metrics.scale, style: .continuous))
    }

    /// 読込、失敗、接続準備状態を一覧上部へ表示します。
    @ViewBuilder
    private var statusBanner: some View {
        if state.phase == .loading {
            Label("garage.status.loading", systemImage: "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
        } else if state.phase == .identifying {
            HStack(spacing: 12 * metrics.scale) {
                ProgressView().controlSize(.small).tint(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("garage.connection.in_progress").font(.headline)
                    Text("garage.identification.loading_hint").font(.caption).opacity(0.82)
                }
            }
            .foregroundStyle(.white)
            .padding(14 * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 15 * metrics.scale, style: .continuous)
            )
        } else if let failureKey = state.failureKey {
            VStack(alignment: .leading, spacing: 5 * metrics.scale) {
                Label(LocalizedStringKey(failureKey), systemImage: "exclamationmark.triangle.fill")
                if let stage = state.identificationFailureStage {
                    HStack(spacing: 4 * metrics.scale) {
                        Text("garage.identification.failure_stage")
                        Text(stage.diagnosticCode)
                    }
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
                .foregroundStyle(.orange)
                .padding(14 * metrics.scale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14 * metrics.scale))
        } else if state.connectionVehicle != nil, state.phase == .readyToConnect {
            Label("garage.connection.handoff", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
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
        let activity = state.activityByVehicleID[vehicle.id] ?? VehicleActivitySummary()
        return VStack(alignment: .leading, spacing: 15 * metrics.scale) {
            ZStack(alignment: .topLeading) {
                vehicleImage(vehicle)
                    .frame(maxWidth: .infinity, minHeight: 165 * metrics.scale, maxHeight: 165 * metrics.scale)
                    .clipped()
                if activity.isConnected {
                    Label("garage.connection.active", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.9), in: Capsule())
                        .padding(10)
                }
                if let modelCode = state.specialPIDModelCodeByVehicleID[vehicle.id] {
                    VehicleModelBadge(modelCode: modelCode)
                        .padding(10 * metrics.scale)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
            }

            Divider().opacity(0.55)
            HStack(spacing: 0) {
                activityMetric(value: "\(activity.sessionCount)", key: "garage.activity.sessions", symbol: "rectangle.stack.fill")
                Divider().frame(height: 32 * metrics.scale)
                activityMetric(value: durationText(activity.totalRecordedDuration), key: "garage.activity.duration", symbol: "clock.fill")
            }

            if let odometer = activity.latestOdometerKilometers {
                HStack(spacing: 7 * metrics.scale) {
                    Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(.tint)
                    Text("garage.activity.odometer").foregroundStyle(.secondary)
                    Spacer()
                    Text(odometer, format: .number.precision(.fractionLength(0...1)))
                        .fontWeight(.semibold)
                    Text("km").foregroundStyle(.secondary)
                    if let modelCode = activity.odometerModelCode {
                        VehicleModelBadge(modelCode: modelCode)
                            .scaleEffect(0.68)
                            .frame(width: 28 * metrics.scale, height: 28 * metrics.scale)
                    }
                }
                .font(.system(size: 11 * metrics.scale))
            }

            HStack(spacing: 7 * metrics.scale) {
                Image(systemName: "calendar.badge.clock").foregroundStyle(.tint)
                Text("garage.activity.last_log").foregroundStyle(.secondary)
                Spacer()
                if let date = activity.lastLoggedAt {
                    Text(date, format: .dateTime.year().month().day().hour().minute()).fontWeight(.semibold)
                } else {
                    Text("garage.activity.no_logs").fontWeight(.semibold)
                }
            }
            .font(.system(size: 11 * metrics.scale))

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
                Button { send(.editRequested(vehicle.id)) } label: { Label("garage.edit", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.borderedProminent)
                Button { send(.pidSettingsRequested(vehicle.id)) } label: { Label("garage.pid_settings.open", systemImage: "waveform.badge.magnifyingglass") }
                Button(role: .destructive) { deletionCandidate = vehicle } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("garage.delete.action")
                .accessibilityIdentifier("macos-garage-delete-\(vehicle.id.rawValue.uuidString)")
                Spacer()
                Image(systemName: "icloud")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("garage.synced"))
            }
        }
        .padding(14 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24 * metrics.scale).stroke(Color.primary.opacity(0.08)) }
        .accessibilityIdentifier("macos-garage-vehicle-\(vehicle.id.rawValue.uuidString)")
    }

    /// 車両別の単一アクティビティ集計を均等幅で表示します。
    ///
    /// 責務: 1件の車両別集計値をmacOSカード用の指標表示へ変換します。
    /// - Parameters:
    ///   - value: 表示する集計値。
    ///   - key: 集計内容のローカライズキー。
    ///   - symbol: 集計内容を補助するSF Symbol名。
    /// - Returns: 車両カード用の指標表示。
    private func activityMetric(value: String, key: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 7 * metrics.scale) {
            Image(systemName: symbol).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 16 * metrics.scale, weight: .bold, design: .rounded))
                Text(key).font(.system(size: 10 * metrics.scale)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8 * metrics.scale)
    }

    /// 記録秒数をカード用の短い時分表記へ変換します。
    ///
    /// 責務: 車両別の累積記録時間をmacOSカード幅へ収まる単一文字列へ変換します。
    /// - Parameter duration: 非負として表示する累積秒数。
    /// - Returns: 時間または分単位の短い表示文字列。
    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration) / 60)
        return totalMinutes >= 60 ? "\(totalMinutes / 60)h \(totalMinutes % 60)m" : "\(totalMinutes)m"
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
                        .accessibilityIdentifier("macos-garage-identification-confirm")
                }
            }
            .padding(36 * metrics.scale)
            .frame(maxWidth: 900 * metrics.scale, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// macOS Garageで車両識別失敗段階を表示文言へ変換します。
private extension VehicleIdentificationError.Stage {
    /// 実機確認で報告できる現在段階の安定診断コードです。
    var diagnosticCode: String {
        switch self {
        case .endpointValidation: "ENDPOINT"
        case .transportCreation: "TRANSPORT-CREATE"
        case .transportOpen: "TRANSPORT-OPEN"
        case .adapterReset: "ATZ"
        case .adapterConfiguration: "AT-CONFIG"
        case .adapterIdentity: "ATI"
        case .vehicleIdentificationRequest: "0902-REQUEST"
        case .vehicleIdentificationParsing: "0902-PARSE"
        case .protocolDescription: "ATDP"
        }
    }
}
#endif
