#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// macOSで写真主導のVehicle Studioとして車両プロフィールを編集します。
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

    /// 編集対象と操作通知先からmacOS Vehicle Studioを生成します。
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

    /// 車両写真と計器パネル風の入力群をウインドウ幅に応じて再配置します。
    ///
    /// 責務: 1件の車両プロフィール編集をmacOS専用のVehicle Studioと確定操作へ変換します。
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                studioHeader
                responsiveEditor
            }
            .padding(30 * metrics.scale)
            .frame(maxWidth: 1_150 * metrics.scale)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.07), Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .center
            )
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
        .accessibilityIdentifier("macos-vehicle-editor")
    }

    /// Vehicle Studioの文脈、戻る操作、確定操作を1列に配置します。
    private var studioHeader: some View {
        HStack(spacing: 14 * metrics.scale) {
            Button { send(.editCancelled) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15 * metrics.scale, weight: .bold))
                    .frame(width: 42 * metrics.scale, height: 42 * metrics.scale)
                    .background(.regularMaterial, in: Circle())
                    .overlay { Circle().stroke(Color.primary.opacity(0.10)) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("garage.cancel")

            VStack(alignment: .leading, spacing: 3 * metrics.scale) {
                Text("garage.editor.studio")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.5 * metrics.scale)
                    .foregroundStyle(.tint)
                Text("garage.editor.title")
                    .font(.system(size: 29 * metrics.scale, weight: .bold, design: .rounded))
            }
            Spacer()
            saveControl
        }
    }

    /// 保存操作を業務ツールバーではなくStudio完了操作として表示します。
    private var saveControl: some View {
        Button { send(.vehicleSaved(draft)) } label: {
            HStack(spacing: 10 * metrics.scale) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12 * metrics.scale, weight: .black))
                    .frame(width: 28 * metrics.scale, height: 28 * metrics.scale)
                    .background(.white.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("garage.save").font(.system(size: 13 * metrics.scale, weight: .bold))
                    Text("garage.editor.save_hint").font(.system(size: 9 * metrics.scale)).opacity(0.76)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14 * metrics.scale)
            .padding(.vertical, 8 * metrics.scale)
            .background(
                LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .shadow(color: Color.blue.opacity(0.22), radius: 12 * metrics.scale, y: 5 * metrics.scale)
        }
        .buttonStyle(.plain)
        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("macos-garage-save")
    }

    /// 利用可能幅に応じて写真と入力パネルを横並びまたは縦並びにします。
    private var responsiveEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22 * metrics.scale) {
                photoPanel.frame(width: 330 * metrics.scale)
                editorPanels
            }
            VStack(spacing: 20 * metrics.scale) {
                photoPanel
                editorPanels
            }
        }
    }

    /// 車両写真、名称、固定識別子をStudioの主表示として描画します。
    private var photoPanel: some View {
        VStack(alignment: .leading, spacing: 15 * metrics.scale) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let data = draft.photoData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [.indigo.opacity(0.92), .blue.opacity(0.62), .black.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 64 * metrics.scale, weight: .medium))
                                .foregroundStyle(.white.opacity(0.86))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4 * metrics.scale) {
                    Text(draft.name.isEmpty ? String(localized: "garage.editor.title") : draft.name)
                        .font(.system(size: 23 * metrics.scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(draft.displayIdentifier)
                        .font(.system(size: 10 * metrics.scale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(18 * metrics.scale)
            }
            .frame(height: 360 * metrics.scale)
            .clipShape(RoundedRectangle(cornerRadius: 25 * metrics.scale, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 25 * metrics.scale).stroke(Color.white.opacity(0.12)) }
            .shadow(color: .black.opacity(0.16), radius: 20 * metrics.scale, y: 10 * metrics.scale)

            Button { isPhotoImporterPresented = true } label: {
                Label("garage.photo.choose", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// 識別、動力、主要諸元の入力カードを縦に配置します。
    private var editorPanels: some View {
        VStack(spacing: 16 * metrics.scale) {
            identityCard
            energyCard
            specificationsCard
        }
        .frame(maxWidth: .infinity)
    }

    /// 車両名称と識別に関する入力欄を表示します。
    private var identityCard: some View {
        editorCard(title: "garage.section.identity", symbol: "person.text.rectangle.fill") {
            LazyVGrid(columns: editorColumns, spacing: 13 * metrics.scale) {
                textInput(title: "garage.field.name", text: $draft.name, symbol: "character.cursor.ibeam")
                textInput(title: "garage.field.manufacturer", text: $draft.manufacturer, symbol: "building.2")
                textInput(title: "garage.field.engine_model", text: $draft.engineModel, symbol: "engine.combustion")
                readOnlyIdentifier
            }
        }
    }

    /// 動力区分とエネルギー源の選択欄を表示します。
    private var energyCard: some View {
        editorCard(title: "garage.section.energy", symbol: "bolt.car.fill") {
            LazyVGrid(columns: editorColumns, spacing: 13 * metrics.scale) {
                pickerInput(title: "garage.field.powertrain", symbol: "gearshape.2") {
                    Picker("garage.field.powertrain", selection: powertrainSelection) {
                        ForEach(VehiclePowertrainKind.allCases, id: \.self) { Text(powertrainLabelKey(for: $0)) }
                    }.labelsHidden()
                }
                pickerInput(title: "garage.field.energy", symbol: "fuelpump.fill") {
                    Picker("garage.field.energy", selection: energySourceSelection) {
                        ForEach(energySources(for: draft.powertrain), id: \.self) { Text(energyLabelKey(for: $0)) }
                    }.labelsHidden()
                }
            }
        }
    }

    /// 年式、タンク容量、メモを入力欄として表示します。
    private var specificationsCard: some View {
        editorCard(title: "garage.section.other", symbol: "gauge.with.dots.needle.67percent") {
            LazyVGrid(columns: editorColumns, spacing: 13 * metrics.scale) {
                yearInput
                tankInput
            }
            VStack(alignment: .leading, spacing: 7 * metrics.scale) {
                inputLabel("garage.field.note", symbol: "note.text")
                TextField("garage.field.note", text: $draft.note, axis: .vertical)
                    .lineLimit(3...7)
                    .padding(11 * metrics.scale)
                    .background(inputBackground)
                    .overlay { inputBorder }
            }
        }
    }

    /// 画面幅へ追従する2列入力グリッドです。
    private var editorColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 210 * metrics.scale), spacing: 13 * metrics.scale)]
    }

    /// 1件の編集領域を見出し付き計器パネルへ変換します。
    ///
    /// 責務: 関連する入力群をmacOS Vehicle Studioの単一カードへまとめます。
    /// - Parameters:
    ///   - title: カード見出しのローカライズキー。
    ///   - symbol: カード内容を示すSF Symbol名。
    ///   - content: カード内へ配置する入力群。
    /// - Returns: macOS用の編集カード。
    private func editorCard<Content: View>(title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14 * metrics.scale) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14 * metrics.scale, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
            content()
        }
        .padding(17 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 19 * metrics.scale).stroke(Color.primary.opacity(0.09)) }
    }

    /// 文字列Bindingを常時境界線のある入力欄へ変換します。
    ///
    /// 責務: 1件の文字列を入力可能と認識できるmacOSフィールドとして描画します。
    /// - Parameters:
    ///   - title: 入力内容のローカライズキー。
    ///   - text: 編集対象文字列。
    ///   - symbol: 入力内容を示すSF Symbol名。
    /// - Returns: ラベル付き文字列入力欄。
    private func textInput(title: LocalizedStringKey, text: Binding<String>, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            inputLabel(title, symbol: symbol)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 11 * metrics.scale)
                .frame(minHeight: 40 * metrics.scale)
                .background(inputBackground)
                .overlay { inputBorder }
        }
    }

    /// Pickerを常時境界線のある選択欄へ変換します。
    ///
    /// 責務: 1件の選択操作を入力可能と認識できるmacOSフィールドとして描画します。
    /// - Parameters:
    ///   - title: 選択内容のローカライズキー。
    ///   - symbol: 選択内容を示すSF Symbol名。
    ///   - content: 入力枠内へ配置するPicker。
    /// - Returns: ラベル付き選択欄。
    private func pickerInput<Content: View>(title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            inputLabel(title, symbol: symbol)
            HStack {
                content()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8 * metrics.scale)
            .frame(minHeight: 40 * metrics.scale)
            .background(inputBackground)
            .overlay { inputBorder }
        }
    }

    /// 年式を桁区切りなしで編集する入力欄です。
    private var yearInput: some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            inputLabel("garage.field.model_year", symbol: "calendar")
            TextField("garage.field.model_year", value: $draft.modelYear, format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .padding(.horizontal, 11 * metrics.scale)
                .frame(minHeight: 40 * metrics.scale)
                .background(inputBackground)
                .overlay { inputBorder }
        }
    }

    /// タンク容量を小数1桁まで編集する入力欄です。
    private var tankInput: some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            inputLabel("garage.field.tank", symbol: "fuelpump")
            TextField("garage.field.tank", value: $draft.tankCapacityLiters, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.plain)
                .padding(.horizontal, 11 * metrics.scale)
                .frame(minHeight: 40 * metrics.scale)
                .background(inputBackground)
                .overlay { inputBorder }
        }
    }

    /// VINまたはOBD識別子を編集不可の情報面として表示します。
    private var readOnlyIdentifier: some View {
        VStack(alignment: .leading, spacing: 7 * metrics.scale) {
            inputLabel(draft.vin.isEmpty ? "garage.field.obd_identifier" : "garage.field.vin", symbol: "number.square")
            Text(draft.displayIdentifier)
                .font(.system(size: 11 * metrics.scale, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40 * metrics.scale, alignment: .leading)
                .padding(.horizontal, 11 * metrics.scale)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10 * metrics.scale))
                .textSelection(.enabled)
        }
    }

    /// 入力内容を示す小型ラベルを返します。
    ///
    /// 責務: 1件の入力名とSF Symbolを統一されたmacOS補助ラベルへ変換します。
    /// - Parameters:
    ///   - title: 入力名のローカライズキー。
    ///   - symbol: 入力内容を示すSF Symbol名。
    /// - Returns: 入力欄上部へ配置するラベル。
    private func inputLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 10 * metrics.scale, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    /// 入力可能領域を示す背景面です。
    private var inputBackground: some ShapeStyle { Color(nsColor: .controlBackgroundColor) }

    /// 入力可能領域を常時識別できる境界線です。
    private var inputBorder: some View {
        RoundedRectangle(cornerRadius: 10 * metrics.scale, style: .continuous)
            .stroke(Color.primary.opacity(0.20), lineWidth: 1)
    }

    /// 1件のエネルギー種別を編集プロフィールへ接続します。
    private var energySourceSelection: Binding<VehicleEnergySource> {
        Binding(
            get: { draft.energySources.first ?? energySources(for: draft.powertrain).first ?? .other },
            set: { draft.energySources = [$0] }
        )
    }

    /// 動力区分の選択をエネルギー源整合化とともに編集プロフィールへ接続します。
    private var powertrainSelection: Binding<VehiclePowertrainKind> {
        Binding(
            get: { draft.powertrain },
            set: { draft.powertrain = $0; sanitizeEnergySourcesForCurrentPowertrain() }
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
    /// 責務: 動力区分選択の表示をローカライズ済みラベルへ固定します。
    /// - Parameter kind: 表示対象の動力区分。
    /// - Returns: ラベルキー。
    private func powertrainLabelKey(for kind: VehiclePowertrainKind) -> LocalizedStringKey {
        switch kind {
        case .combustion: "garage.powertrain.combustion"
        case .hybrid: "garage.powertrain.hybrid"
        case .plugInHybrid: "garage.powertrain.plugInHybrid"
        case .batteryElectric: "garage.powertrain.batteryElectric"
        case .fuelCell: "garage.powertrain.fuelCell"
        case .other: "garage.powertrain.other"
        }
    }

    /// 1件のエネルギー源をローカライズキーへ変換します。
    ///
    /// 責務: エネルギー種別選択の表示を翻訳済み文言へ変換します。
    /// - Parameter source: 表示対象のエネルギー源。
    /// - Returns: ラベルキー。
    private func energyLabelKey(for source: VehicleEnergySource) -> LocalizedStringKey {
        switch source {
        case .gasolinePremium: "garage.energy.gasolinePremium"
        case .gasolineRegular: "garage.energy.gasolineRegular"
        case .gasoline: "garage.energy.gasoline"
        case .diesel: "garage.energy.diesel"
        case .lpg: "garage.energy.lpg"
        case .cng: "garage.energy.cng"
        case .hydrogen: "garage.energy.hydrogen"
        case .electricity: "garage.energy.electricity"
        case .other: "garage.energy.other"
        }
    }

    /// 駆動区分変更時にエネルギー選択を再構築します。
    ///
    /// 責務: 選択済みエネルギー源を現在区分で利用可能な範囲へ再整列させます。
    private func sanitizeEnergySourcesForCurrentPowertrain() {
        draft.energySources = VehicleEnergySourcePolicy.normalizedSources(draft.energySources, for: draft.powertrain)
    }

    /// 保存済みエネルギー源を編集開始状態へ準備します。
    ///
    /// 責務: 空のエネルギー源だけを現在の動力区分に合う既定値で補完します。
    private func prepareEnergySourcesForEditing() {
        draft.energySources = VehicleEnergySourcePolicy.sourcesForEditing(draft.energySources, powertrain: draft.powertrain)
    }
}
#endif
