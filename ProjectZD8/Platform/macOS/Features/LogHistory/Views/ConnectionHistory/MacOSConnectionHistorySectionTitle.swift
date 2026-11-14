#if os(macOS)
import SwiftUI

/// 接続履歴のセクション見出しです。
struct MacOSConnectionHistorySectionTitle: View {
    /// 見出しのローカライズキーです。
    let titleKey: LocalizedStringKey
    /// 見出しを補助するSF Symbol名です。
    let systemImage: String
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// シンボル付きの見出しを描画します。
    ///
    /// 責務: 1件の見出しキーとシンボルを履歴セクション見出しへ変換します。
    var body: some View {
        Label(titleKey, systemImage: systemImage)
            .font(.system(size: 18 * scale, weight: .bold, design: .rounded))
            .padding(.horizontal, 2 * scale)
    }
}
#endif
