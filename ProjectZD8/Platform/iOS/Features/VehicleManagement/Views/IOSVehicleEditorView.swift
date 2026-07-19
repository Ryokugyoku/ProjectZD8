#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// iPhoneで新規または既存の車両プロフィールを編集します。
struct IOSVehicleEditorView: View {
    /// 保存前の編集値です。
    @State private var draft: VehicleProfile
    /// 写真選択シートの表示状態です。
    @State private var isPhotoImporterPresented = false
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
                TextField("garage.field.model_year", value: $draft.modelYear, format: .number)
            }
            Section("garage.section.energy") {
                Picker("garage.field.powertrain", selection: $draft.powertrain) {
                    ForEach(VehiclePowertrainKind.allCases, id: \.self) { kind in
                        Text(LocalizedStringKey("garage.powertrain.\(kind.rawValue)"))
                    }
                }
                ForEach(VehicleEnergySource.allCases, id: \.self) { source in
                    Toggle(LocalizedStringKey("garage.energy.\(source.rawValue)"), isOn: energyBinding(source))
                }
                TextField("garage.field.tank", value: $draft.tankCapacityLiters, format: .number)
                    .keyboardType(.decimalPad)
            }
            Section("garage.section.other") {
                TextField("garage.field.note", text: $draft.note, axis: .vertical)
                Toggle("garage.field.default", isOn: $draft.isDefault)
            }
            Section {
                Button("garage.save") { send(.vehicleSaved(draft)) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("garage.cancel", role: .cancel) { send(.editCancelled) }
                    .frame(maxWidth: .infinity)
            }
        }
        .fileImporter(isPresented: $isPhotoImporterPresented, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result { send(.photoSelected(url)) }
        }
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
}
#endif
