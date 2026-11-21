#if os(macOS)
import SwiftUI

/// macOS のセッション詳細へ抑制された奥行きを与える背景です。
struct MacOSConnectionSessionDetailBackground: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// ウインドウ背景色に右上からのインディゴの放射グラデーションを重ねます。
    ///
    /// 責務: 倍率に応じた放射半径で詳細画面の背景を描画します。
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.indigo.opacity(0.085), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 620 * scale
            )
        }
    }
}
#endif
