#if os(iOS)
import PhotosUI
import SwiftUI

/// 写真の追加・説明・削除のセクションです。写真は端末の写真から選びます。
struct IOSMaintenancePhotosSection: View {
    let editor: MaintenanceEditorState
    let send: (MaintenanceAction) -> Void

    @State private var pickedItems: [PhotosPickerItem] = []

    var body: some View {
        Section {
            ForEach(editor.draft.photos) { photo in
                HStack(alignment: .top, spacing: InsightSpacing.md) {
                    IOSPhotoThumbnail(data: editor.photoData[photo.id], side: IOSAppShellMetrics.maintenancePhotoSide)
                    VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                        TextField(
                            "maintenance.photo.caption",
                            text: Binding(get: { photo.caption }, set: { send(.photoCaptionChanged(photo.id, $0)) }),
                            axis: .vertical
                        )
                        .lineLimit(1...4)
                        if editor.photoData[photo.id] == nil {
                            Label("maintenance.photo.unavailable", systemImage: "exclamationmark.triangle.fill")
                                .font(InsightTypography.footnote)
                                .foregroundStyle(InsightPalette.warning)
                        }
                        Button(role: .destructive) { send(.photoRemoved(photo.id)) } label: {
                            Label("maintenance.photo.remove", systemImage: "trash")
                        }
                        .font(InsightTypography.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
            PhotosPicker(selection: $pickedItems, matching: .images) {
                Label("maintenance.photo.add", systemImage: "photo.badge.plus")
            }
        } header: {
            Text("maintenance.editor.photos")
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        send(.photoPicked(data))
                    }
                }
                pickedItems = []
            }
        }
    }
}
#endif
