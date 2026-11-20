#if os(macOS)
import SwiftUI

/// 未接続時のmacOSホームの目的を短く示す見出しです。
struct MacOSHomeHeading: View {
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 小見出し、題名、説明を縦に並べます。
    ///
    /// 責務: ホームの見出しを描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            Text("home.eyebrow")
                .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                .tracking(1.8 * scale)
                .foregroundStyle(.tint)
            Text("home.title")
                .font(.system(size: 34 * scale, weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            Text("home.subtitle")
                .font(.system(size: 14 * scale, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
#endif
