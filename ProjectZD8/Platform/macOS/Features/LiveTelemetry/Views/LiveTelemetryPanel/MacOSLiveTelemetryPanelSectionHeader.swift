#if os(macOS)
import SwiftUI

/// リアルタイム表示パネルの区画見出しです。
struct MacOSLiveTelemetryPanelSectionHeader: View {
    /// 見出しのローカライズキーです。
    let titleKey: String
    /// 見出しを補助するSF Symbol名です。
    let symbol: String
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 記号付きの見出しを描画します。
    ///
    /// 責務: 1件の見出しキーと記号を同じ視覚階層の見出しへ描画します。
    var body: some View {
        Label(LocalizedStringKey(titleKey), systemImage: symbol)
            .font(.system(size: 18 * scale, weight: .bold, design: .rounded))
            .accessibilityAddTraits(.isHeader)
    }
}
#endif
