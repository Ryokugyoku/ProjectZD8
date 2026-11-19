#if os(iOS)
import SwiftUI

/// 製品名とモバイル向けの標語を示すホームのブランド表示です。
struct IOSHomeBrandHeader: View {
    /// 記号と製品名、標語を横に並べます。
    ///
    /// 責務: ホーム上端のブランド表示を描画します。
    var body: some View {
        HStack(spacing: 12) {
            brandIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("RevTorque Insight")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text("ios.shell.tagline")
                    .font(.system(size: IOSHomeMetrics.brandTaglineFontSize, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// アクセント色のグラデーションに計器の記号を重ねた表示です。
    private var brandIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: IOSHomeMetrics.brandIconCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.accentColor.opacity(0.25), radius: 10, y: 4)
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: IOSHomeMetrics.brandIconFontSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: IOSHomeMetrics.brandIconSize, height: IOSHomeMetrics.brandIconSize)
    }
}
#endif
