#if os(iOS)
import SwiftUI

/// iPhoneのセッション解析で使う、見出しと説明を持つ共通のカード枠です。
struct IOSSessionLogAnalysisCard<Content: View>: View {
    /// カード見出しのローカライズキーです。
    let title: LocalizedStringKey
    /// カード説明のローカライズキーです。
    let subtitle: LocalizedStringKey
    /// カード内へ描画する解析内容です。
    let content: Content

    /// 見出し・説明・内容を固定してカードを生成します。
    ///
    /// 責務: 1件の解析内容を見出しと説明付きのカードとして保持します。
    /// - Parameters:
    ///   - title: カード見出しのローカライズキー。
    ///   - subtitle: カード説明のローカライズキー。
    ///   - content: カード内へ描画する解析内容。
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    /// 接続履歴と同じ素材階層の解析カードです。
    ///
    /// 責務: 見出し・説明・内容を縦に並べ、角丸の素材背景で囲みます。
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(.title3.weight(.bold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.07)) }
    }
}
#endif
