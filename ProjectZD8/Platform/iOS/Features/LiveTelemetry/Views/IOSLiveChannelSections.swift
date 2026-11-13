#if os(iOS)
import SwiftUI

/// チャンネルを `OBDPIDCategory` ごとにまとめ、タイルの格子で並べます。
struct IOSLiveChannelSections: View {
    let live: LiveTelemetryState

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xl) {
            if live.channels.isEmpty, live.status == .live {
                Text("live.channels.awaiting")
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(OBDPIDCategory.allCases, id: \.self) { category in
                let channels = live.channels(in: category)
                if !channels.isEmpty {
                    VStack(alignment: .leading, spacing: InsightSpacing.md) {
                        InsightSectionHeader(Text(LocalizedStringKey(category.nameKey)))
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: IOSAppShellMetrics.channelTileMinimumWidth), spacing: InsightSpacing.md, alignment: .top)],
                            alignment: .leading,
                            spacing: InsightSpacing.md
                        ) {
                            ForEach(channels) { channel in
                                IOSLiveChannelTile(channel: channel, isStale: live.isStale)
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
