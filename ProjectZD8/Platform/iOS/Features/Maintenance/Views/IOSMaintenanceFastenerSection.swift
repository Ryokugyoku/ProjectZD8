#if os(iOS)
import SwiftUI

/// 重整備の締結グループ(分解本数と組立時の個別締結証跡)の入力セクションです。
struct IOSMaintenanceFastenerSection: View {
    let editor: MaintenanceEditorState
    @Binding var draft: MaintenanceDraft
    let send: (MaintenanceAction) -> Void

    var body: some View {
        ForEach($draft.fastenerGroups) { $group in
            IOSFastenerGroupSection(group: $group, editor: editor, send: send)
        }
        Section {
            Button { send(.fastenerGroupAdded) } label: {
                Label("maintenance.fastener.addGroup", systemImage: "plus.circle")
            }
        } header: {
            Text("maintenance.editor.fasteners")
        } footer: {
            Text("maintenance.editor.fasteners.footer")
        }
    }
}
#endif
