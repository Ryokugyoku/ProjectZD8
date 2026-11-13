#if os(iOS)
import SwiftUI

/// 1本の締結の証跡(位置・トルク・工具・担当・完了日時・写真)の入力セクションです。
struct IOSFastenerEvidenceSection: View {
    let groupID: UUID
    @Binding var evidence: FastenerInstallationEvidence
    let editor: MaintenanceEditorState
    let send: (MaintenanceAction) -> Void

    var body: some View {
        Section {
            TextField("maintenance.fastener.position", text: $evidence.position)
            TextField("maintenance.fastener.torque", value: $evidence.torqueNewtonMeters, format: .number)
                .keyboardType(.decimalPad)
            TextField("maintenance.fastener.tool", text: $evidence.tool)
            TextField("maintenance.fastener.tightenedBy", text: $evidence.tightenedBy)
            HStack {
                if let date = evidence.tightenedAt {
                    Label {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(InsightPalette.positive)
                    }
                } else {
                    Label("maintenance.fastener.notConfirmed", systemImage: "circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("maintenance.fastener.confirm") {
                    send(.fastenerConfirmed(groupID: groupID, evidenceID: evidence.id))
                }
                .buttonStyle(.borderless)
            }
            IOSMaintenancePhotoLinks(
                title: "maintenance.fastener.photos",
                photos: editor.draft.photos,
                photoData: editor.photoData,
                linked: evidence.photoIDs,
                onLink: { send(.fastenerPhotoLinked(groupID: groupID, evidenceID: evidence.id, photoID: $0)) },
                onUnlink: { send(.fastenerPhotoUnlinked(groupID: groupID, evidenceID: evidence.id, photoID: $0)) }
            )
            TextField("maintenance.fastener.notes", text: $evidence.notes, axis: .vertical)
                .lineLimit(1...4)
            Button("maintenance.fastener.removeFastener", role: .destructive) {
                send(.fastenerRemoved(groupID: groupID, evidenceID: evidence.id))
            }
        } header: {
            Text("maintenance.editor.fastener")
        }
    }
}
#endif
