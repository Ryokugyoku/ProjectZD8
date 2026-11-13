#if os(macOS)
import SwiftUI

/// 1チャンネルの現在値と直近履歴を示すタイル。
struct MacOSChannelTile: View {
    let channel: LiveTelemetryChannel
    let isStale: Bool

    var body: some View {
        VStack(spacing: InsightSpacing.xs) {
            MetricTile(
                label: Text(LocalizedStringKey(channel.nameKey)),
                value: channel.value.map { Text(verbatim: Self.format($0)) },
                unit: channel.unit.isEmpty ? nil : Text(verbatim: channel.unit),
                secondary: statusText,
                isStale: isStale,
                staleText: Text("drive.live.stale"),
                unavailableText: unavailableText
            )
            if channel.history.count > 1 {
                SparklineView(
                    values: channel.history.map { Optional($0.value) },
                    range: channel.minimumValue.flatMap { low in channel.maximumValue.map { low...$0 } },
                    accessibilityLabel: Text(LocalizedStringKey(channel.nameKey)),
                    accessibilityValue: channel.value.map { Text(verbatim: Self.format($0)) }
                )
                .frame(height: 32)
                .opacity(isStale ? 0.4 : 1)
            }
        }
    }

    /// 値が無い理由(応答なし・範囲外など)。有効値の時は何も出さない。
    private var statusText: Text? {
        switch channel.validity {
        case .valid: nil
        case .awaiting, .outOfRange, .decodeFailed, .noResponse: unavailableText
        }
    }

    private var unavailableText: Text? {
        switch channel.validity {
        case .valid: nil
        case .awaiting: Text("drive.live.awaiting")
        case .outOfRange: Text("drive.live.outOfRange")
        case .decodeFailed: Text("drive.live.decodeFailed")
        case .noResponse: Text("drive.live.noResponse")
        }
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
#endif
