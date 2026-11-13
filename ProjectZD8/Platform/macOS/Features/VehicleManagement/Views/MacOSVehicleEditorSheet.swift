#if os(macOS)
import SwiftUI

/// 車両プロフィールの編集シート。全ての下書き項目・検証結果・写真の設定/削除を扱う。
struct MacOSVehicleEditorSheet: View {
    let editor: VehicleEditorState
    let send: (VehicleManagementAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    photoRow
                }
                Section {
                    TextField(text: field(\.name)) { Text("garage.field.name") }
                    TextField(text: field(\.manufacturer)) { Text("garage.field.manufacturer") }
                    TextField(text: field(\.engineModel)) { Text("garage.field.engine") }
                    TextField(value: optionalField(\.modelYear), format: .number.grouping(.never)) {
                        Text("garage.field.modelYear")
                    }
                    LabeledContent {
                        Text(verbatim: editor.draft.vin.isEmpty ? "—" : editor.draft.vin)
                            .font(InsightTypography.numeric(.body))
                            .textSelection(.enabled)
                    } label: {
                        Text("garage.field.vin")
                    }
                } header: {
                    Text("garage.section.identity")
                }
                Section {
                    Picker(selection: field(\.powertrain)) {
                        ForEach(VehiclePowertrainOption.all) { option in
                            Text(LocalizedStringKey(option.nameKey)).tag(option.kind)
                        }
                    } label: {
                        Text("garage.field.powertrain")
                    }
                    ForEach(editor.draft.energySourceOptions) { option in
                        Toggle(isOn: Binding(
                            get: { option.isSelected },
                            set: { _ in
                                var next = editor.draft
                                next.toggleEnergySource(option.source)
                                send(.draftChanged(next))
                            }
                        )) {
                            Text(LocalizedStringKey(option.nameKey))
                        }
                    }
                    TextField(value: optionalField(\.tankCapacityLiters), format: .number) {
                        Text("garage.field.tank")
                    }
                } header: {
                    Text("garage.section.powertrain")
                }
                Section {
                    TextField(text: field(\.note), axis: .vertical) { Text("garage.field.note") }
                        .lineLimit(3...8)
                } header: {
                    Text("garage.section.note")
                }
                if !editor.issues.isEmpty {
                    Section {
                        ForEach(editor.issues, id: \.localizationKey) { issue in
                            Label {
                                Text(LocalizedStringKey(issue.localizationKey))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(InsightPalette.warning)
                            }
                            .font(InsightTypography.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if editor.isSaving { ProgressView().controlSize(.small) }
                Spacer()
                Button(role: .cancel) {
                    send(.editCancelled)
                } label: {
                    Text("common.cancel")
                }
                .keyboardShortcut(.cancelAction)
                .disabled(editor.isSaving)
                Button {
                    send(.saveRequested)
                } label: {
                    Text("common.save")
                }
                .buttonStyle(.insightPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(editor.isSaving || !editor.issues.isEmpty)
            }
            .padding(InsightSpacing.lg)
        }
        .frame(width: MacOSAppShellMetrics.editorSheetWidth)
        .frame(minHeight: MacOSAppShellMetrics.editorSheetMinHeight)
        .interactiveDismissDisabled(editor.isSaving)
    }

    private var photoRow: some View {
        HStack(spacing: InsightSpacing.lg) {
            VehicleAvatar(imageData: editor.photoData, name: editor.draft.name, size: 80)
            VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                MacOSPhotoSourceMenu(title: editor.photoData == nil ? "garage.photo.set" : "garage.photo.replace") {
                    send(.photoPicked($0))
                }
                if editor.photoData != nil {
                    Button(role: .destructive) {
                        send(.photoRemoved)
                    } label: {
                        Label("garage.photo.remove", systemImage: "trash")
                    }
                }
            }
            Spacer()
        }
    }

    private func field<Value>(_ keyPath: WritableKeyPath<VehicleEditDraft, Value>) -> Binding<Value> {
        Binding(
            get: { editor.draft[keyPath: keyPath] },
            set: { value in
                var next = editor.draft
                next[keyPath: keyPath] = value
                send(.draftChanged(next))
            }
        )
    }

    private func optionalField<Value>(_ keyPath: WritableKeyPath<VehicleEditDraft, Value?>) -> Binding<Value?> {
        field(keyPath)
    }
}
#endif
