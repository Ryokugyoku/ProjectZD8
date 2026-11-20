#if os(iOS)
import SwiftUI

/// 履歴一覧のセクション見出しです。
struct IOSConnectionHistorySectionTitle: View {
    /// 見出しのローカライズキーです。
    let titleKey: LocalizedStringKey
    /// 見出しを補助するSF Symbol名です。
    let systemImage: String

    /// シンボル付きの見出しを描画します。
    ///
    /// 責務: 1件の見出しキーとシンボルを履歴セクション見出しへ配置します。
    var body: some View {
        Label(titleKey, systemImage: systemImage).font(.system(.title3, design: .rounded, weight: .bold)).padding(.horizontal, 2)
    }
}
#endif
