#if os(macOS)
import SwiftUI

/// 整備記録のエディタシート。基本項目・作業項目・写真・(重整備のみ)締結部を編集する。
struct MacOSMaintenanceEditorSheet: View {
    let editor: MaintenanceEditorState
    let send: (MaintenanceAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent {
                        StatusBadge(Text(LocalizedStringKey(editor.draft.kind.localizationKey)), tone: editor.draft.kind == .heavy ? .warning : .active)
                    } label: {
                        Text("maintenance.field.kind")
                    }
                    TextField(text: field(\.title)) { Text("maintenance.field.title") }
                    DatePicker(selection: field(\.performedAt), displayedComponents: [.date, .hourAndMinute]) {
                        Text("maintenance.field.performedAt")
                    }
                    TextField(value: field(\.odometerKilometers), format: .number) {
                        Text("maintenance.field.odometer")
                    }
                    TextField(text: field(\.notes), axis: .vertical) { Text("maintenance.field.notes") }
                        .lineLimit(2...6)
                } header: {
                    Text("maintenance.section.basics")
                }

                MacOSMaintenanceWorkItemsSection(draft: editor.draft, send: send)
                MacOSMaintenancePhotosSection(draft: editor.draft, photoData: editor.photoData, send: send)
                if editor.draft.kind == .heavy {
                    MacOSMaintenanceFastenersSection(draft: editor.draft, photoData: editor.photoData, issues: editor.issues, send: send)
                }

                if !editor.issues.isEmpty {
                    Section {
                        ForEach(Array(editor.issues), id: \.self) { issue in
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
        .frame(width: MacOSAppShellMetrics.editorSheetWidth + 80)
        .frame(minHeight: MacOSAppShellMetrics.editorSheetMinHeight + 120)
        .interactiveDismissDisabled(editor.isSaving)
    }

    private func field<Value>(_ keyPath: WritableKeyPath<MaintenanceDraft, Value>) -> Binding<Value> {
        Binding(
            get: { editor.draft[keyPath: keyPath] },
            set: { value in
                var next = editor.draft
                next[keyPath: keyPath] = value
                send(.draftChanged(next))
            }
        )
    }
}
#endif
