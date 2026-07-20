#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// iPhoneで新規または既存の車両プロフィールを編集します。
struct IOSVehicleEditorView: View {
    /// 保存前の編集値です。
    @State private var draft: VehicleProfile
    /// 写真選択シートの表示状態です。
    @State private var isPhotoImporterPresented = false
    /// 現在編集中の元プロフィールです。
    let vehicle: VehicleProfile
    /// 車両管理操作の通知先です。
    let send: (VehicleManagementAction) -> Void

    /// 編集対象をiPhone用フォーム状態へ複製します。
    ///
    /// 責務: 1件の車両プロフィールを保存前のiPhone編集状態へ複製します。
    /// - Parameters:
    ///   - vehicle: 編集対象プロフィール。
    ///   - send: 型付き操作の通知先。
    init(vehicle: VehicleProfile, send: @escaping (VehicleManagementAction) -> Void) {
        _draft = State(initialValue: vehicle)
        self.vehicle = vehicle
        self.send = send
    }

    /// 片手操作とDynamic Typeに追従する車両入力フォームを提供します。
    ///
    /// 責務: 1件の車両プロフィール編集を保存または取消操作へ変換します。
    var body: some View {
        Form {
            Section("garage.photo") {
                photoPreview
                Button("garage.photo.choose") { isPhotoImporterPresented = true }
            }
            Section("garage.section.identity") {
                TextField("garage.field.name", text: $draft.name)
                LabeledContent(draft.vin.isEmpty ? "garage.field.obd_identifier" : "garage.field.vin", value: draft.displayIdentifier)
                TextField("garage.field.manufacturer", text: $draft.manufacturer)
                TextField("garage.field.engine_model", text: $draft.engineModel)
            }
            Section("garage.section.energy") {
                Picker("garage.field.powertrain", selection: powertrainSelection) {
                    ForEach(VehiclePowertrainKind.allCases, id: \.self) { kind in
                        Text(powertrainLabelKey(for: kind))
                    }
                }
                Picker("garage.field.energy", selection: energySourceSelection) {
                    ForEach(energySources(for: draft.powertrain), id: \.self) { source in
                        Text(energyLabelKey(for: source))
                    }
                }
                .pickerStyle(.menu)
            }
            Section("garage.section.other") {
                TextField("garage.field.tank", value: $draft.tankCapacityLiters, format: .number)
                    .keyboardType(.decimalPad)
                TextField("garage.field.model_year", value: $draft.modelYear, format: .number)
                TextField("garage.field.note", text: $draft.note, axis: .vertical)
                Toggle("garage.field.default", isOn: $draft.isDefault)
            }
        }
        .navigationTitle("garage.editor.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("garage.cancel", role: .cancel) { send(.editCancelled) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("garage.save") { send(.vehicleSaved(draft)) }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .fileImporter(isPresented: $isPhotoImporterPresented, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result { send(.photoSelected(url)) }
        }
        .onAppear {
            draft = vehicle
            prepareEnergySourcesForEditing()
        }
        .onChange(of: vehicle) { _, newValue in
            draft = newValue
            prepareEnergySourcesForEditing()
        }
        .accessibilityIdentifier("ios-vehicle-editor")
    }

    /// 写真または未設定状態をアスペクト比を保って表示します。
    private var photoPreview: some View {
        Group {
            if let data = draft.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.accentColor.opacity(0.5), .black.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 170)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    /// 1件のエネルギー種別を編集プロフィールへ接続します。
    ///
    /// 責務: エネルギー種別の選択状態を編集プロフィールの単一選択値として同期します。
    /// - Returns: エネルギー種別選択を編集プロフィールへ接続するBinding。
    private var energySourceSelection: Binding<VehicleEnergySource> {
        Binding(
            get: {
                draft.energySources.first ?? energySources(for: draft.powertrain).first ?? .other
            },
            set: { selectedSource in
                draft.energySources = [selectedSource]
            }
        )
    }

    /// 動力区分の選択をエネルギー源整合化とともに編集プロフィールへ接続します。
    ///
    /// 責務: ユーザーが選んだ動力区分を反映し、エネルギー源を新しい区分へ整合させます。
    /// - Returns: 動力区分選択を編集プロフィールへ接続するBinding。
    private var powertrainSelection: Binding<VehiclePowertrainKind> {
        Binding(
            get: { draft.powertrain },
            set: { newPowertrain in
                draft.powertrain = newPowertrain
                sanitizeEnergySourcesForCurrentPowertrain()
            }
        )
    }

    /// 駆動システム別に表示するエネルギー源を返します。
    ///
    /// 責務: 動力区分に対する運用可能なエネルギー種別だけを編集UIへ限定します。
    /// - Parameter powertrain: 現在編集中の駆動システム。
    /// - Returns: 表示対象のエネルギー源配列。
    private func energySources(for powertrain: VehiclePowertrainKind) -> [VehicleEnergySource] {
        VehicleEnergySourcePolicy.availableSources(for: powertrain)
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
    /// 責務: エネルギー種別選択をキー表示ではなく翻訳済み文言へ変換します。
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
    /// 責務: 選択済みエネルギー源を失わずに現在区分で利用可能な範囲へ再整列させます。
    private func sanitizeEnergySourcesForCurrentPowertrain() {
        draft.energySources = VehicleEnergySourcePolicy.normalizedSources(
            draft.energySources,
            for: draft.powertrain
        )
    }

    /// 保存済みエネルギー源を編集開始状態へ準備します。
    ///
    /// 責務: 保存済み値を失わずに空のエネルギー源だけを既定値で補完します。
    private func prepareEnergySourcesForEditing() {
        draft.energySources = VehicleEnergySourcePolicy.sourcesForEditing(
            draft.energySources,
            powertrain: draft.powertrain
        )
    }
}
#endif
