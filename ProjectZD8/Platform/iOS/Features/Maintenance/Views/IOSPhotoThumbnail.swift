#if os(iOS)
import SwiftUI

/// 画像データを縮小デコードして角丸の正方形に示します。データが無い・読めない場合は代替アイコンです。
struct IOSPhotoThumbnail: View {
    let data: Data?
    let side: CGFloat

    @State private var decoded: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous).fill(InsightPalette.surfaceRaised)
            if let decoded {
                Image(decorative: decoded, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous))
        .task(id: data) {
            guard let data else { decoded = nil; return }
            let pixels = Int(side * 3)
            decoded = await Task.detached(priority: .userInitiated) { try? VehicleImageDecoder.decode(data, maxPixelSize: pixels) }.value
        }
        .accessibilityHidden(true)
    }
}
#endif
