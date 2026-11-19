#if os(iOS)
import SwiftUI

/// 未接続時のホームの目的を短く示す見出しです。
struct IOSHomeHeading: View {
    /// 小見出し、題名、説明を縦に並べます。
    ///
    /// 責務: ホームの見出しを描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("home.eyebrow")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(.tint)
            Text("home.title")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("home.subtitle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
