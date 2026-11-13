#if os(iOS)
import SwiftUI

/// 登録済みの写真を関連付ける・外す操作です。関連付けた写真を小さなサムネイルで並べます。
struct IOSMaintenancePhotoLinks: View {
    let title: LocalizedStringKey
    let photos: [MaintenancePhoto]
    let photoData: [PhotoID: Data]
    let linked: [PhotoID]
    let onLink: (PhotoID) -> Void
    let onUnlink: (PhotoID) -> Void

    private let thumbnailSide: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.sm) {
            HStack {
                Text(title).font(InsightTypography.label)
                Spacer()
                Menu {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button { onLink(photo.id) } label: {
                            if photo.caption.isEmpty {
                                Text("maintenance.photo.numbered \(index + 1)")
                            } else {
                                Text(verbatim: photo.caption)
                            }
                        }
                        .disabled(linked.contains(photo.id))
                    }
                } label: {
                    Label("maintenance.photo.link", systemImage: "link.badge.plus")
                        .font(InsightTypography.caption)
                }
                .disabled(photos.isEmpty)
            }
            if !linked.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: InsightSpacing.sm) {
                        ForEach(linked, id: \.self) { id in
                            IOSPhotoThumbnail(data: photoData[id], side: thumbnailSide)
                                .overlay(alignment: .topTrailing) {
                                    Button { onUnlink(id) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .frame(minWidth: InsightSpacing.minimumHitTarget / 2, minHeight: InsightSpacing.minimumHitTarget / 2)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(Text("maintenance.photo.unlink"))
                                }
                        }
                    }
                }
            }
        }
    }
}
#endif
