#if os(iOS)
import SwiftUI

/// リアルタイム表示パネルの区画見出しです。
struct IOSLiveTelemetryPanelSectionHeader: View {
    /// 見出しのローカライズキーです。
    let titleKey: String
    /// 見出しを補助するSF Symbol名です。
    let symbol: String

    /// 記号付きの見出しを描画します。
    ///
    /// 責務: 1件の見出しキーと記号を同じ視覚階層の見出しへ描画します。
    var body: some View {
        Label(LocalizedStringKey(titleKey), systemImage: symbol)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .accessibilityAddTraits(.isHeader)
    }
}
#endif
