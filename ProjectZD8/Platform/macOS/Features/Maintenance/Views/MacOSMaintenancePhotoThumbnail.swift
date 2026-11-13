#if os(macOS)
import SwiftUI

/// 整備写真のサムネイル。デコードできない時は欠測の枠を出す。
struct MacOSMaintenancePhotoThumbnail: View {
    let data: Data?
    var size: CGFloat = 72

    @State private var decoded: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: InsightRadius.xs, style: .continuous).fill(InsightPalette.surfaceRaised)
            if let decoded {
                Image(decorative: decoded, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: InsightRadius.xs, style: .continuous))
        .task(id: data) {
            guard let data else { decoded = nil; return }
            let side = Int(size * 3)
            decoded = await Task.detached(priority: .userInitiated) { try? VehicleImageDecoder.decode(data, maxPixelSize: side) }.value
        }
        .accessibilityHidden(true)
    }
}
#endif
