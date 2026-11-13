#if os(macOS)
import SwiftUI

/// 整備エディタの写真セクション(追加・キャプション・削除)。
struct MacOSMaintenancePhotosSection: View {
    let draft: MaintenanceDraft
    let photoData: [PhotoID: Data]
    let send: (MaintenanceAction) -> Void

    var body: some View {
        Section {
            ForEach(draft.photos) { photo in
                HStack(spacing: InsightSpacing.md) {
                    MacOSMaintenancePhotoThumbnail(data: photoData[photo.id])
                    VStack(alignment: .leading, spacing: InsightSpacing.xs) {
                        TextField(
                            text: Binding(
                                get: { photo.caption },
                                set: { send(.photoCaptionChanged(photo.id, $0)) }
                            )
                        ) {
                            Text("maintenance.photo.caption")
                        }
                        Text(photo.capturedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(InsightTypography.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        send(.photoRemoved(photo.id))
                    } label: {
                        Label("maintenance.photo.remove", systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }
            }
            MacOSPhotoSourceMenu(title: "maintenance.photo.add") { send(.photoPicked($0)) }
        } header: {
            Text("maintenance.section.photos")
        }
    }
}
#endif
