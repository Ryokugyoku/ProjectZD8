#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// macOSでユーザー編集可能な車両プロフィールを入力します。
struct MacOSVehicleEditorView: View {
    /// 保存前の編集値です。
    @State private var draft: VehicleProfile
    /// 写真ファイル選択の表示状態です。
    @State private var isPhotoImporterPresented = false
    /// 現在編集中の元プロフィールです。
    let vehicle: VehicleProfile
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 編集対象と操作通知先からmacOSエディターを生成します。
    ///
    /// 責務: 1件の車両プロフィールを保存前のmacOS編集状態へ複製します。
    /// - Parameters:
    ///   - vehicle: 編集対象プロフィール。
    ///   - send: 型付き操作の通知先。
    ///   - metrics: ウインドウ対応寸法。
    init(vehicle: VehicleProfile, send: @escaping (VehicleManagementAction) -> Void, metrics: MacOSAppShellMetrics) {
        _draft = State(initialValue: vehicle)
        self.vehicle = vehicle
        self.send = send
        self.metrics = metrics
    }

    /// 写真、名称、動力分類、エネルギー源、任意諸元の編集画面を提供します。
    ///
    /// 責務: 1件の車両プロフィール編集を型付き保存または取消操作へ変換します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                Text("garage.editor.title")
                    .font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))

                HStack(alignment: .top, spacing: 26 * metrics.scale) {
                    photoPanel
                    form
                }

                HStack {
                    Button("garage.cancel") { send(.editCancelled) }
                    Spacer()
                    Button("garage.save") { send(.vehicleSaved(draft)) }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("macos-garage-save")
                }
            }
            .padding(34 * metrics.scale)
            .frame(maxWidth: 1_020 * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .fileImporter(isPresented: $isPhotoImporterPresented, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result { send(.photoSelected(url)) }
        }
        .onAppear {
            draft = vehicle
            sanitizeEnergySourcesForCurrentPowertrain()
        }
        .onChange(of: vehicle) { newValue in
            draft = newValue
            sanitizeEnergySourcesForCurrentPowertrain()
        }
    }

    /// 写真プレビューと選択操作です。
    private var photoPanel: some View {
        VStack(spacing: 14) {
            Group {
                if let data = draft.photoData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [.accentColor.opacity(0.5), .black.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "camera.fill").font(.system(size: 42)).foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 270 * metrics.scale, height: 180 * metrics.scale)
            .clipShape(RoundedRectangle(cornerRadius: 24 * metrics.scale))

            Button("garage.photo.choose") { isPhotoImporterPresented = true }
        }
    }

    /// ユーザー編集可能な全テキスト値と分類値です。
    private var form: some View {
        Form {
            TextField("garage.field.name", text: $draft.name)
            LabeledContent(draft.vin.isEmpty ? "garage.field.obd_identifier" : "garage.field.vin", value: draft.displayIdentifier)
            TextField("garage.field.manufacturer", text: $draft.manufacturer)
            TextField("garage.field.engine_model", text: $draft.engineModel)
            Picker("garage.field.powertrain", selection: $draft.powertrain) {
                ForEach(VehiclePowertrainKind.allCases, id: \.self) { kind in
                    Text(powertrainLabelKey(for: kind))
                }
            }
            .onChange(of: draft.powertrain) { _ in
                sanitizeEnergySourcesForCurrentPowertrain()
            }
            Section("garage.field.energy") {
                ForEach(energySources(for: draft.powertrain), id: \.self) { source in
                    Toggle(energyLabelKey(for: source), isOn: energyBinding(source))
                }
            }
            TextField("garage.field.tank", value: $draft.tankCapacityLiters, format: .number)
            TextField("garage.field.model_year", value: $draft.modelYear, format: .number)
            TextField("garage.field.note", text: $draft.note, axis: .vertical)
            Toggle("garage.field.default", isOn: $draft.isDefault)
        }
        .formStyle(.grouped)
        .frame(maxWidth: 580 * metrics.scale)
    }

    /// 1件のエネルギー源を配列内の選択状態へ変換します。
    ///
    /// 責務: 指定エネルギー源の選択操作だけを編集プロフィールへ反映します。
    /// - Parameter source: 選択状態を読み書きするエネルギー源。
    /// - Returns: 配列要素の有無へ接続したBinding。
    private func energyBinding(_ source: VehicleEnergySource) -> Binding<Bool> {
        Binding {
            draft.energySources.contains(source)
        } set: { isSelected in
            if isSelected, !draft.energySources.contains(source) { draft.energySources.append(source) }
            if !isSelected { draft.energySources.removeAll { $0 == source } }
        }
    }

    /// 駆動システム別に表示するエネルギー源を返します。
    ///
    /// 責務: 動力区分に対する運用可能なエネルギー種別だけを編集UIへ限定します。
    /// - Parameter powertrain: 現在編集中の駆動システム。
    /// - Returns: 表示対象のエネルギー源配列。
    private func energySources(for powertrain: VehiclePowertrainKind) -> [VehicleEnergySource] {
        switch powertrain {
        case .combustion:
            return [.gasolinePremium, .gasolineRegular, .diesel]
        case .hybrid, .plugInHybrid:
            return [.gasolinePremium, .gasolineRegular, .diesel, .electricity]
        case .batteryElectric:
            return [.electricity]
        case .fuelCell:
            return [.hydrogen]
        case .other:
            return [.other]
        }
    }

    /// 1件の動力区分をローカライズキーへ変換します。
    ///
    /// 責務: 動力区分選択の表示をキー文字列ではなくローカライズ済みラベルへ固定します。
    /// - Parameter kind: 表示対象の動力区分。
    /// - Returns: ラベルキー。
    private func powertrainLabelKey(for kind: VehiclePowertrainKind) -> LocalizedStringKey {
        switch kind {
        case .combustion:
            "garage.powertrain.combustion"
        case .hybrid:
            "garage.powertrain.hybrid"
        case .plugInHybrid:
            "garage.powertrain.plugInHybrid"
        case .batteryElectric:
            "garage.powertrain.batteryElectric"
        case .fuelCell:
            "garage.powertrain.fuelCell"
        case .other:
            "garage.powertrain.other"
        }
    }

    /// 1件のエネルギー源をローカライズキーへ変換します。
    ///
    /// 責務: エネルギー種別トグルをキー表示ではなく翻訳済み文言へ変換します。
    /// - Parameter source: 表示対象のエネルギー源。
    /// - Returns: ラベルキー。
    private func energyLabelKey(for source: VehicleEnergySource) -> LocalizedStringKey {
        switch source {
        case .gasolinePremium:
            "garage.energy.gasolinePremium"
        case .gasolineRegular:
            "garage.energy.gasolineRegular"
        case .gasoline:
            "garage.energy.gasoline"
        case .diesel:
            "garage.energy.diesel"
        case .lpg:
            "garage.energy.lpg"
        case .cng:
            "garage.energy.cng"
        case .hydrogen:
            "garage.energy.hydrogen"
        case .electricity:
            "garage.energy.electricity"
        case .other:
            "garage.energy.other"
        }
    }

    /// 駆動区分変更時にエネルギー選択を再構築します。
    ///
    /// 責務: 選択済みエネルギー源を現在区分で利用可能なものへ再整列させます。
    private func sanitizeEnergySourcesForCurrentPowertrain() {
        let available = energySources(for: draft.powertrain)
        draft.energySources.removeAll { !available.contains($0) }
        if draft.energySources.isEmpty {
            draft.energySources = [available.first].compactMap { $0 }
        }
    }
}
#endif
