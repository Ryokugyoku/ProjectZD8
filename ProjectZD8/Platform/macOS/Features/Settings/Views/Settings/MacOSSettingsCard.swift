#if os(macOS)
import SwiftUI

/// macOS設定画面で設定カテゴリごとに共通の見出しと操作領域を持つカードを描画します。
struct MacOSSettingsCard<Content: View>: View {
    /// カテゴリを短く識別するローカライズキーです。
    let eyebrow: LocalizedStringKey
    /// 設定カードのタイトルです。
    let title: LocalizedStringKey
    /// 設定内容を補足するローカライズキーです。
    let description: LocalizedStringKey
    /// カテゴリを表すSF Symbol名です。
    let systemImage: String
    /// ウインドウ寸法に応じた拡大率を持つ寸法です。
    let metrics: MacOSAppShellMetrics
    /// カード下部へ配置する操作または状態表示です。
    let content: Content

    /// 見出しと操作領域を指定してカードを生成します。
    ///
    /// 責務: 1件の設定カテゴリの見出し文言と操作領域を保持します。
    /// - Parameters:
    ///   - eyebrow: カテゴリを短く識別するローカライズキー。
    ///   - title: 設定カードのタイトル。
    ///   - description: 設定内容を補足するローカライズキー。
    ///   - systemImage: カテゴリを表すSF Symbol名。
    ///   - metrics: 現在のウインドウに対応する表示寸法。
    ///   - content: カード下部へ配置する操作または状態表示。
    init(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        systemImage: String,
        metrics: MacOSAppShellMetrics,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.metrics = metrics
        self.content = content()
    }

    /// 統一された見出しと操作領域を持つカードを提供します。
    ///
    /// 責務: 1件の設定カテゴリをmacOS設定画面の視覚階層へ揃えて描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: 16 * metrics.scale) {
            header
            content
        }
        .padding(18 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    /// アイコン、カテゴリ、タイトル、説明を並べた見出しです。
    private var header: some View {
        HStack(alignment: .top, spacing: 12 * metrics.scale) {
            Image(systemName: systemImage)
                .font(.system(size: 16 * metrics.scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34 * metrics.scale, height: 34 * metrics.scale)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 10 * metrics.scale, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3 * metrics.scale) {
                Text(eyebrow)
                    .font(.system(size: 9 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.2 * metrics.scale)
                    .foregroundStyle(.tint)

                Text(title)
                    .font(.system(size: 17 * metrics.scale, weight: .bold, design: .rounded))

                Text(description)
                    .font(.system(size: 11.5 * metrics.scale, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
#endif
