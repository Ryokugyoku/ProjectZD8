#if os(macOS)
import SwiftUI

/// 「情報」タブ: アプリ名とバージョン。
struct MacOSAboutSettingsView: View {
    let versionText: String

    var body: some View {
        VStack(spacing: InsightSpacing.md) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 44))
                .foregroundStyle(InsightPalette.accent)
                .accessibilityHidden(true)
            Text("settings.about.appName").font(InsightTypography.screenTitle)
            LabeledContent {
                Text(verbatim: versionText).font(InsightTypography.numeric(.body))
            } label: {
                Text("settings.about.version")
            }
            .frame(maxWidth: 260)
        }
        .padding(InsightSpacing.xxl)
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}
#endif
