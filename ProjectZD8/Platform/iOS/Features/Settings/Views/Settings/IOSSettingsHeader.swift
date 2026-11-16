#if os(iOS)
import SwiftUI

/// iOS設定画面の目的を示すモバイル向け見出しを描画します。
struct IOSSettingsHeader: View {
    /// アイコンとタイトル・副題を並べた見出しを提供します。
    ///
    /// 責務: 設定画面の先頭に、画面の目的を示す見出しを描画します。
    var body: some View {
        HStack(alignment: .center, spacing: IOSSettingsMetrics.headerSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: IOSSettingsMetrics.headerIconCornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(IOSSettingsMetrics.headerIconFillOpacity))

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: IOSSettingsMetrics.headerIconFontSize, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: IOSSettingsMetrics.headerIconSize, height: IOSSettingsMetrics.headerIconSize)
            .overlay {
                RoundedRectangle(cornerRadius: IOSSettingsMetrics.headerIconCornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(IOSSettingsMetrics.headerIconStrokeOpacity), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: IOSSettingsMetrics.headerTextSpacing) {
                Text("settings.title")
                    .font(.system(.title, design: .rounded, weight: .bold))

                Text("settings.subtitle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, IOSSettingsMetrics.headerBottomPadding)
    }
}
#endif
