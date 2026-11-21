#if os(macOS)
import SwiftUI

/// macOSのセッション解析で使う、見出しと説明を持つ共通のカード枠です。
struct MacOSSessionLogAnalysisCard<Content: View>: View {
    /// カード見出しのローカライズキーです。
    let title: LocalizedStringKey
    /// カード説明のローカライズキーです。
    let subtitle: LocalizedStringKey
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// カード内へ描画する解析内容です。
    let content: Content

    /// 見出し・説明・寸法・内容を固定してカードを生成します。
    ///
    /// 責務: 1件の解析内容を見出しと説明付きのカードとして保持します。
    /// - Parameters:
    ///   - title: カード見出しのローカライズキー。
    ///   - subtitle: カード説明のローカライズキー。
    ///   - metrics: 現在のウインドウ寸法に対応する表示寸法。
    ///   - content: カード内へ描画する解析内容。
    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        metrics: MacOSAppShellMetrics,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.metrics = metrics
        self.content = content()
    }

    /// 接続履歴と同じ素材階層の解析カードです。
    ///
    /// 責務: 見出し・説明・内容を縦に並べ、角丸の素材背景で囲みます。
    var body: some View {
        VStack(alignment: .leading, spacing: 14 * metrics.scale) {
            Text(title).font(.system(size: 20 * metrics.scale, weight: .bold, design: .rounded))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content
        }
        .padding(20 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous).stroke(Color.primary.opacity(0.07)) }
    }
}
#endif
