#if os(iOS)
import SwiftUI

/// iOS設定画面で設定カテゴリごとに共通の見出しと操作領域を持つカードを描画します。
struct IOSSettingsCard<Content: View>: View {
    /// カテゴリを短く識別するローカライズキーです。
    let eyebrow: LocalizedStringKey
    /// 設定カードのタイトルです。
    let title: LocalizedStringKey
    /// 設定内容を補足するローカライズキーです。
    let description: LocalizedStringKey
    /// カテゴリを表すSF Symbol名です。
    let systemImage: String
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
    ///   - content: カード下部へ配置する操作または状態表示。
    init(
        eyebrow: LocalizedStringKey,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.content = content()
    }

    /// 統一された見出しと操作領域を持つカードを提供します。
    ///
    /// 責務: 1件の設定カテゴリをiOS設定画面の視覚階層へ揃えて描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSSettingsMetrics.cardSpacing) {
            header
            content
        }
        .padding(IOSSettingsMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IOSSettingsMetrics.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    /// アイコン、カテゴリ、タイトル、説明を並べた見出しです。
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: IOSSettingsMetrics.cardIconSize, height: IOSSettingsMetrics.cardIconSize)
                .background(
                    Color.accentColor.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: IOSSettingsMetrics.cardIconCornerRadius, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(.tint)

                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))

                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
#endif
