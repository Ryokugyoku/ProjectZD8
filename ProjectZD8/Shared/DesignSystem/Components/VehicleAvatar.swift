import SwiftUI

/// 車両の丸いアバター。写真バイト列があれば表示し、無い/デコードできない場合は頭文字のモノグラムにする。
struct VehicleAvatar: View {
    private let imageData: Data?
    private let name: String
    private let size: CGFloat
    private let accessibilityLabelText: Text?

    @State private var decoded: CGImage?

    /// アバターを作る。
    ///
    /// 責務: 写真データと車両名(モノグラム元)を保持する。
    /// - Parameters:
    ///   - name: 車両名(モノグラムの元。ユーザー入力でありローカライズ対象ではない)。
    ///   - accessibilityLabel: 読み上げ名。nil なら装飾扱いで読み上げない。
    init(imageData: Data?, name: String, size: CGFloat = 48, accessibilityLabel: Text? = nil) {
        self.imageData = imageData
        self.name = name
        self.size = size
        self.accessibilityLabelText = accessibilityLabel
    }

    var body: some View {
        ZStack {
            if let decoded {
                Image(decorative: decoded, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(InsightPalette.accent.opacity(0.16))
                Text(verbatim: VehicleImageDecoder.monogram(from: name))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(InsightPalette.accent)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(InsightPalette.stroke, lineWidth: 1))
        .task(id: imageData) {
            guard let data = imageData else { decoded = nil; return }
            let side = Int(size * 3)
            // 画像として解釈できないバイト列は仕様どおりモノグラムへフォールバックする。
            decoded = await Task.detached(priority: .userInitiated) { try? VehicleImageDecoder.decode(data, maxPixelSize: side) }.value
        }
        .modifier(AvatarAccessibility(label: accessibilityLabelText))
    }
}

/// ラベルがあれば画像として公開し、無ければ読み上げから隠す。
private struct AvatarAccessibility: ViewModifier {
    let label: Text?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityElement().accessibilityLabel(label).accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}

#Preview("Light") {
    HStack(spacing: 16) {
        VehicleAvatar(imageData: nil, name: "Honda S2000")
        VehicleAvatar(imageData: Data([0, 1, 2]), name: "ZD8", size: 64)
        VehicleAvatar(imageData: nil, name: "", size: 32)
    }
    .padding()
    .background(InsightBackground())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VehicleAvatar(imageData: nil, name: "Subaru BRZ", size: 80)
        .padding()
        .background(InsightBackground())
        .preferredColorScheme(.dark)
}
