#if os(iOS)
import SwiftUI

/// 整備記録を編集するシートです。基本情報・作業項目・写真・締結グループ(重整備)を1つのフォームで扱います。
struct IOSMaintenanceEditorView: View {
    let editor: MaintenanceEditorState
    let failure: MaintenanceFailure?
    let pendingDeletion: MaintenanceDeletionPrompt?
    let send: (MaintenanceAction) -> Void

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
                if !editor.issues.isEmpty { issuesSection }
                IOSMaintenanceBasicsSection(draft: draft)
                IOSMaintenanceWorkItemsSection(draft: draft, send: send)
                IOSMaintenancePhotosSection(editor: editor, send: send)
                if editor.draft.kind == .heavy {
                    IOSMaintenanceFastenerSection(editor: editor, draft: draft, send: send)
                }
                if !editor.isNew, let recordID = editor.draft.recordID {
                    Section {
                        Button("maintenance.editor.delete", role: .destructive) { send(.deleteRequested(recordID)) }
                    }
                }
            }
            .navigationTitle(Text(editor.isNew ? "maintenance.editor.titleNew" : "maintenance.editor.titleEdit"))
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
            .insightProgressOverlay(isPresented: editor.isSaving, title: Text("maintenance.editor.saving"))
            .confirmationDialog(
                Text("maintenance.delete.title"),
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { send(.deleteCancelled) } }),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { _ in
                Button("maintenance.delete.confirm", role: .destructive) { send(.deleteConfirmed) }
                Button("common.cancel", role: .cancel) { send(.deleteCancelled) }
            } message: { prompt in
                Text("maintenance.delete.message \(prompt.title) \(prompt.photoCount)")
            }
        }
        .interactiveDismissDisabled(editor.isSaving)
    }

    private var draft: Binding<MaintenanceDraft> {
        Binding(get: { editor.draft }, set: { send(.draftChanged($0)) })
    }

    private var issuesSection: some View {
        Section {
            ForEach(editor.issues, id: \.self) { issue in
                Label(LocalizedStringKey(issue.localizationKey), systemImage: "exclamationmark.triangle.fill")
                    .font(InsightTypography.caption)
                    .foregroundStyle(InsightPalette.warning)
            }
        }
    }
}
#endif
