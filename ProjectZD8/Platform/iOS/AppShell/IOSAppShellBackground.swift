#if os(iOS)
import SwiftUI

/// iOS AppShell全体に共通する奥行きのある背景を描画します。
struct IOSAppShellBackground: View {
    /// システム背景と低彩度のアクセント光を重ねます。
    ///
    /// 責務: iOS AppShellのコンテンツ背後へ装飾専用の背景を描画します。
    var body: some View {
        ZStack {
            Color(.systemBackground)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear,
                    Color.orange.opacity(0.025)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 150, y: -280)

            Circle()
                .fill(Color.orange.opacity(0.035))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: -150, y: 320)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
#endif
