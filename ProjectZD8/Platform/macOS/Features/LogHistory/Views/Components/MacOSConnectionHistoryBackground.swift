#if os(macOS)
import SwiftUI

/// 接続履歴の各画面へ抑制された奥行きを与える背景です。
struct MacOSConnectionHistoryBackground: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// ウインドウ背景色に右上からのアクセント放射グラデーションを重ねます。
    ///
    /// 責務: 倍率に応じた放射半径で履歴画面の背景を描画します。
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.075), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 620 * scale
            )
        }
    }
}
#endif
