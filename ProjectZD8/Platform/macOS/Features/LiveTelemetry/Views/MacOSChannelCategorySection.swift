#if os(macOS)
import SwiftUI

/// カテゴリごとにチャンネルタイルを並べるセクション。
struct MacOSChannelCategorySection: View {
    let category: OBDPIDCategory
    let channels: [LiveTelemetryChannel]
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.md) {
            InsightSectionHeader(Text(LocalizedStringKey(category.nameKey)))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: InsightSpacing.md, alignment: .top)],
                alignment: .leading,
                spacing: InsightSpacing.md
            ) {
                ForEach(channels) { channel in
                    MacOSChannelTile(channel: channel, isStale: isStale)
                }
            }
        }
    }
}
#endif
