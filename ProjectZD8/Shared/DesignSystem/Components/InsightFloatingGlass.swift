import SwiftUI

/// フローティング操作・ナビゲーション層専用の Liquid Glass 修飾。内容カードには使わない。
///
/// Reduce Transparency が有効なときは、ガラスの代わりに不透明な面+縁にする。
private struct InsightFloatingGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(shape.fill(.background))
                .overlay(shape.strokeBorder(InsightPalette.strokeStrong, lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

extension View {
    /// 浮いたコントロール群へ Liquid Glass を適用する。
    ///
    /// 責務: 透明度低減を尊重しつつ、指定角丸のガラス面を背面に付ける。
    func insightFloatingGlass(cornerRadius: CGFloat = InsightRadius.xl) -> some View {
        modifier(InsightFloatingGlassModifier(cornerRadius: cornerRadius))
    }
}

#Preview("Light") {
    ZStack {
        InsightBackground()
        HStack {
            Image(systemName: "play.fill")
            Image(systemName: "stop.fill")
        }
        .padding()
        .insightFloatingGlass()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    ZStack {
        InsightBackground()
        HStack {
            Image(systemName: "play.fill")
            Image(systemName: "stop.fill")
        }
        .padding()
        .insightFloatingGlass()
    }
    .preferredColorScheme(.dark)
}
