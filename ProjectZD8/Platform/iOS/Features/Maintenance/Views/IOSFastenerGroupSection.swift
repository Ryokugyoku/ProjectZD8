#if os(iOS)
import SwiftUI

/// 1つの締結グループ(名称・位置・本数・分解状態の写真・個別締結)の入力セクションです。
struct IOSFastenerGroupSection: View {
    @Binding var group: MaintenanceFastenerGroup
    let editor: MaintenanceEditorState
    let send: (MaintenanceAction) -> Void

    var body: some View {
        Section {
            TextField("maintenance.fastener.groupName", text: $group.name)
            TextField("maintenance.fastener.location", text: $group.location)
            TextField("maintenance.fastener.expectedCount", value: $group.expectedCount, format: .number)
                .keyboardType(.numberPad)
            Stepper(value: $group.removedCount, in: 0...9999) {
                HStack {
                    Text("maintenance.fastener.removedCount")
                    Spacer()
                    Text(group.removedCount, format: .number).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            TextField("maintenance.fastener.removalNotes", text: $group.removalNotes, axis: .vertical)
                .lineLimit(1...6)
            IOSMaintenancePhotoLinks(
                title: "maintenance.fastener.removalPhotos",
                photos: editor.draft.photos,
                photoData: editor.photoData,
                linked: group.removalPhotoIDs,
                onLink: { send(.removalPhotoLinked(groupID: group.id, photoID: $0)) },
                onUnlink: { send(.removalPhotoUnlinked(groupID: group.id, photoID: $0)) }
            )
            Button("maintenance.fastener.removeGroup", role: .destructive) { send(.fastenerGroupRemoved(group.id)) }
        } header: {
            Text("maintenance.editor.fastenerGroup")
        }
        ForEach($group.installations) { $evidence in
            IOSFastenerEvidenceSection(groupID: group.id, evidence: $evidence, editor: editor, send: send)
        }
        Section {
            Button { send(.fastenerAdded(groupID: group.id)) } label: {
                Label("maintenance.fastener.addFastener", systemImage: "plus.circle")
            }
        }
    }
}
#endif
