#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// iPhoneで車両写真を中心にプロフィールと主要諸元を編集します。
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

    /// 写真、識別情報、動力構成、主要諸元を明確な入力面として表示します。
    ///
    /// 責務: 1件の車両プロフィール編集をカード型入力と保存・取消操作へ変換します。
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                editorHeader
                photoHero
                identityCard
                energyCard
                specificationsCard
                saveButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), Color(.systemGroupedBackground), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .center
            ).ignoresSafeArea()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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

    /// Vehicle Studioの文脈と戻る操作を一体化して表示します。
    private var editorHeader: some View {
        HStack(spacing: 13) {
            Button { send(.editCancelled) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .overlay { Circle().stroke(Color.primary.opacity(0.10)) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("garage.cancel")

            VStack(alignment: .leading, spacing: 2) {
                Text("garage.editor.studio")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.tint)
                Text("garage.editor.title")
                    .font(.system(.title2, design: .rounded, weight: .bold))
            }
            Spacer()
        }
    }

    /// 写真と現在の車両名称を編集画面の主役として表示します。
    private var photoHero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let data = draft.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [.indigo.opacity(0.9), .blue.opacity(0.65), .black.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 58, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 224, maxHeight: 224)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name.isEmpty ? String(localized: "garage.editor.title") : draft.name)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(draft.displayIdentifier)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(18)

            Button { isPhotoImporterPresented = true } label: {
                Label("garage.photo.choose", systemImage: "camera.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.12)) }
        .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
    }

    /// 名称、メーカー、エンジン型式、固定識別子を表示します。
    private var identityCard: some View {
        editorCard(title: "garage.section.identity", symbol: "person.text.rectangle.fill") {
            textInput(title: "garage.field.name", text: $draft.name, symbol: "character.cursor.ibeam")
            textInput(title: "garage.field.manufacturer", text: $draft.manufacturer, symbol: "building.2")
            textInput(title: "garage.field.engine_model", text: $draft.engineModel, symbol: "engine.combustion")
            readOnlyIdentifier
        }
    }

    /// 動力区分とエネルギー源を選択可能な入力面として表示します。
    private var energyCard: some View {
        editorCard(title: "garage.section.energy", symbol: "bolt.car.fill") {
            pickerInput(title: "garage.field.powertrain", symbol: "gearshape.2") {
                Picker("garage.field.powertrain", selection: powertrainSelection) {
                    ForEach(VehiclePowertrainKind.allCases, id: \.self) { kind in
                        Text(powertrainLabelKey(for: kind))
                    }
                }
                .labelsHidden()
            }
            pickerInput(title: "garage.field.energy", symbol: "fuelpump.fill") {
                Picker("garage.field.energy", selection: energySourceSelection) {
                    ForEach(energySources(for: draft.powertrain), id: \.self) { source in
                        Text(energyLabelKey(for: source))
                    }
                }
                .labelsHidden()
            }
        }
    }

    /// 年式、タンク容量、メモを明確な入力欄として表示します。
    private var specificationsCard: some View {
        editorCard(title: "garage.section.other", symbol: "gauge.with.dots.needle.67percent") {
            HStack(alignment: .top, spacing: 12) {
                numericInput(
                    title: "garage.field.model_year",
                    value: $draft.modelYear,
                    format: .number.grouping(.never),
                    symbol: "calendar"
                )
                numericInput(
                    title: "garage.field.tank",
                    value: $draft.tankCapacityLiters,
                    format: .number.precision(.fractionLength(0...1)),
                    symbol: "fuelpump"
                )
            }
            VStack(alignment: .leading, spacing: 7) {
                inputLabel("garage.field.note", symbol: "note.text")
                TextField("garage.field.note", text: $draft.note, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(13)
                    .background(inputBackground)
                    .overlay { inputBorder }
            }
        }
    }

    /// 変更内容を保存する主要操作を大きなボタンとして表示します。
    private var saveButton: some View {
        Button { send(.vehicleSaved(draft)) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.18)).frame(width: 38, height: 38)
                    Image(systemName: "checkmark").font(.headline.weight(.black))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("garage.save").font(.headline)
                    Text("garage.editor.save_hint").font(.caption).opacity(0.78)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .shadow(color: Color.blue.opacity(0.28), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        .accessibilityIdentifier("ios-garage-save")
    }

    /// 1件の編集領域を見出し付きカードへ変換します。
    ///
    /// 責務: 関連する入力群を単一の視覚階層へまとめます。
    /// - Parameters:
    ///   - title: カード見出しのローカライズキー。
    ///   - symbol: カード内容を示すSF Symbol名。
    ///   - content: カード内へ配置する入力群。
    /// - Returns: iPhone用の編集カード。
    private func editorCard<Content: View>(
        title: LocalizedStringKey,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: symbol)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)
            content()
        }
        .padding(17)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.09)) }
    }

    /// 文字列入力をラベルと常時表示枠を持つ入力欄へ変換します。
    ///
    /// 責務: 1件の文字列Bindingを入力可能と識別できるiPhoneフィールドとして描画します。
    /// - Parameters:
    ///   - title: 入力内容のローカライズキー。
    ///   - text: 編集対象文字列。
    ///   - symbol: 入力内容を示すSF Symbol名。
    /// - Returns: ラベル付き文字列入力欄。
    private func textInput(title: LocalizedStringKey, text: Binding<String>, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            inputLabel(title, symbol: symbol)
            TextField(title, text: text)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 13)
                .frame(minHeight: 48)
                .background(inputBackground)
                .overlay { inputBorder }
        }
    }

    /// 数値Bindingを桁区切り方針付きの入力欄へ変換します。
    ///
    /// 責務: 1件の任意数値を指定FormatStyleで編集できるiPhoneフィールドとして描画します。
    /// - Parameters:
    ///   - title: 入力内容のローカライズキー。
    ///   - value: 編集対象の任意数値。
    ///   - format: 入出力へ適用する数値書式。
    ///   - symbol: 入力内容を示すSF Symbol名。
    /// - Returns: ラベル付き数値入力欄。
    private func numericInput<Value: BinaryFloatingPoint, Format: ParseableFormatStyle>(
        title: LocalizedStringKey,
        value: Binding<Value?>,
        format: Format,
        symbol: String
    ) -> some View where Format.FormatInput == Value, Format.FormatOutput == String {
        VStack(alignment: .leading, spacing: 7) {
            inputLabel(title, symbol: symbol)
            TextField(title, value: value, format: format)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 13)
                .frame(minHeight: 48)
                .background(inputBackground)
                .overlay { inputBorder }
        }
        .frame(maxWidth: .infinity)
    }

    /// 整数Bindingを桁区切り方針付きの入力欄へ変換します。
    ///
    /// 責務: 1件の任意整数を指定FormatStyleで編集できるiPhoneフィールドとして描画します。
    /// - Parameters:
    ///   - title: 入力内容のローカライズキー。
    ///   - value: 編集対象の任意整数。
    ///   - format: 入出力へ適用する整数書式。
    ///   - symbol: 入力内容を示すSF Symbol名。
    /// - Returns: ラベル付き整数入力欄。
    private func numericInput<Format: ParseableFormatStyle>(
        title: LocalizedStringKey,
        value: Binding<Int?>,
        format: Format,
        symbol: String
    ) -> some View where Format.FormatInput == Int, Format.FormatOutput == String {
        VStack(alignment: .leading, spacing: 7) {
            inputLabel(title, symbol: symbol)
            TextField(title, value: value, format: format)
                .keyboardType(.numberPad)
                .padding(.horizontal, 13)
                .frame(minHeight: 48)
                .background(inputBackground)
                .overlay { inputBorder }
        }
        .frame(maxWidth: .infinity)
    }

    /// Pickerをラベルと入力枠を持つ選択欄へ変換します。
    ///
    /// 責務: 1件の選択操作を入力欄として認識できる外観へ包みます。
    /// - Parameters:
    ///   - title: 選択内容のローカライズキー。
    ///   - symbol: 選択内容を示すSF Symbol名。
    ///   - content: 入力枠内へ配置するPicker。
    /// - Returns: ラベル付き選択欄。
    private func pickerInput<Content: View>(
        title: LocalizedStringKey,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            inputLabel(title, symbol: symbol)
            HStack {
                content()
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .background(inputBackground)
            .overlay { inputBorder }
        }
    }

    /// VINまたはOBD識別子を編集不可の情報面として表示します。
    private var readOnlyIdentifier: some View {
        VStack(alignment: .leading, spacing: 7) {
            inputLabel(draft.vin.isEmpty ? "garage.field.obd_identifier" : "garage.field.vin", symbol: "number.square")
            Text(draft.displayIdentifier)
                .font(.callout.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 13)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                .textSelection(.enabled)
        }
    }

    /// 入力内容を示す小型ラベルを返します。
    ///
    /// 責務: 1件の入力名とSF Symbolを統一された補助ラベルへ変換します。
    /// - Parameters:
    ///   - title: 入力名のローカライズキー。
    ///   - symbol: 入力内容を示すSF Symbol名。
    /// - Returns: 入力欄上部へ配置するラベル。
    private func inputLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// 入力可能領域を示す背景面です。
    private var inputBackground: some ShapeStyle {
        Color(.secondarySystemGroupedBackground)
    }

    /// 入力可能領域を常時識別できる境界線です。
    private var inputBorder: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
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
