#if os(iOS)
import PhotosUI
import SwiftUI

/// 車両の全項目を編集するシートです。検証の問題は入力の下へ示し、写真は選択・削除できます。
struct IOSVehicleEditorView: View {
    let editor: VehicleEditorState
    let failure: VehicleManagementFailure?
    let send: (VehicleManagementAction) -> Void

    @State private var pickedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                if let failure {
                    InlineBanner(
                        .error,
                        message: Text(LocalizedStringKey(failure.localizationKey)),
                        action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                photoSection
                basicSection
                powertrainSection
                if !editor.issues.isEmpty { issuesSection }
                identifiersSection
            }
            .navigationTitle(Text("garage.editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { send(.editCancelled) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { send(.saveRequested) }
                        .disabled(editor.isSaving || !editor.issues.isEmpty)
                }
            }
            .insightProgressOverlay(isPresented: editor.isSaving, title: Text("garage.editor.saving"))
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        send(.photoPicked(data))
                    }
                    pickedPhoto = nil
                }
            }
        }
        .interactiveDismissDisabled(editor.isSaving)
    }

    private var draft: Binding<VehicleEditDraft> {
        Binding(get: { editor.draft }, set: { send(.draftChanged($0)) })
    }

    private var photoSection: some View {
        Section {
            HStack(spacing: InsightSpacing.lg) {
                VehicleAvatar(imageData: editor.photoData, name: editor.draft.name, size: IOSAppShellMetrics.vehicleEditorPhotoSize)
                VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label(editor.photoData == nil ? "garage.editor.photo.add" : "garage.editor.photo.change", systemImage: "photo")
                    }
                    if editor.draft.photoID != nil || editor.photoData != nil {
                        Button(role: .destructive) { send(.photoRemoved) } label: {
                            Label("garage.editor.photo.remove", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("garage.editor.photo")
        }
    }

    private var basicSection: some View {
        Section {
            TextField("garage.field.name", text: draft.name)
            TextField("garage.field.manufacturer", text: draft.manufacturer)
            TextField("garage.field.engineModel", text: draft.engineModel)
            TextField("garage.field.modelYear", value: draft.modelYear, format: .number.grouping(.never))
                .keyboardType(.numberPad)
            TextField("garage.field.tankCapacity", value: draft.tankCapacityLiters, format: .number)
                .keyboardType(.decimalPad)
            TextField("garage.field.note", text: draft.note, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("garage.editor.basic")
        }
    }

    private var powertrainSection: some View {
        Section {
            Picker("garage.field.powertrain", selection: draft.powertrain) {
                ForEach(VehiclePowertrainOption.all) { option in
                    Text(LocalizedStringKey(option.nameKey)).tag(option.kind)
                }
            }
            ForEach(editor.draft.energySourceOptions) { option in
                Toggle(
                    LocalizedStringKey(option.nameKey),
                    isOn: Binding(
                        get: { option.isSelected },
                        set: { _ in
                            var next = editor.draft
                            next.toggleEnergySource(option.source)
                            send(.draftChanged(next))
                        }
                    )
                )
            }
        } header: {
            Text("garage.field.energySources")
        }
    }

    private var issuesSection: some View {
        Section {
            ForEach(editor.issues, id: \.localizationKey) { issue in
                Label(LocalizedStringKey(issue.localizationKey), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(InsightPalette.warning)
                    .font(InsightTypography.caption)
            }
        }
    }

    private var identifiersSection: some View {
        Section {
            LabeledContent("garage.field.vin") {
                if editor.draft.vin.isEmpty {
                    Text("common.unavailable").foregroundStyle(.secondary)
                } else {
                    Text(verbatim: editor.draft.vin).font(.body.monospaced()).textSelection(.enabled)
                }
            }
            if let identifier = editor.draft.obdIdentifier {
                LabeledContent("garage.field.obdIdentifier") { Text(verbatim: identifier).font(.body.monospaced()) }
            }
        } header: {
            Text("garage.editor.identifiers")
        } footer: {
            Text("garage.editor.identifiers.footer")
        }
    }
}
#endif
