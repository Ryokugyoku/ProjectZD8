#if os(iOS)
import SwiftUI

/// 1つのチャンネルの現在値と直近の履歴を、1枚のカードにまとめて示すタイルです。
struct IOSLiveChannelTile: View {
    let channel: LiveTelemetryChannel
    let isStale: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xs) {
            Text(LocalizedStringKey(channel.nameKey))
                .font(InsightTypography.label)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.xs) {
                if let value = channel.value {
                    Text(value, format: .number.precision(.fractionLength(0...1)))
                        .font(InsightTypography.metricValue)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if !channel.unit.isEmpty {
                        Text(verbatim: channel.unit)
                            .font(InsightTypography.metricUnit)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(verbatim: "—")
                        .font(InsightTypography.metricValue)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(Text("common.unavailable"))
                }
            }
            .opacity(isStale ? 0.5 : 1)
            statusLine
            SparklineView(
                values: channel.history.map { Optional($0.value) },
                style: .area,
                accessibilityLabel: Text(LocalizedStringKey(channel.nameKey))
            )
            .frame(height: IOSAppShellMetrics.sparklineHeight)
            .opacity(isStale ? 0.5 : (channel.history.count > 1 ? 1 : 0))
        }
        .padding(InsightSpacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous).fill(InsightPalette.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: InsightRadius.sm, style: .continuous).strokeBorder(InsightPalette.border(for: contrast), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// 古い値・無効な値の理由を1行で示します。常に1行分の高さを確保して行の高さを揃えます。
    private var statusLine: some View {
        Group {
            if isStale {
                Label("live.channel.stale", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(InsightPalette.warning)
            } else if let text = validityText {
                text.foregroundStyle(.secondary)
            } else {
                Text(verbatim: " ")
            }
        }
        .font(InsightTypography.footnote)
        .lineLimit(1)
    }

    private var validityText: Text? {
        switch channel.validity {
        case .awaiting: Text("live.channel.awaiting")
        case .valid: nil
        case .outOfRange(let value): Text("live.channel.outOfRange \(value.formatted(.number.precision(.fractionLength(0...1))))")
        case .decodeFailed: Text("live.channel.decodeFailed")
        case .noResponse: Text("live.channel.noResponse")
        }
    }
}
#endif
