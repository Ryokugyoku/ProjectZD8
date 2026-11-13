#if os(macOS)
import SwiftUI

/// 記録中(および終了直後)のライブダッシュボード。RPM・速度の大型ゲージとカテゴリ別タイル。
struct MacOSLiveDashboardView: View {
    let telemetry: LiveTelemetryState

    private var gaugeChannels: Set<OBDPIDRequest> { [LiveTelemetryState.rpmRequest, LiveTelemetryState.speedRequest] }

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xl) {
            HStack(alignment: .top, spacing: InsightSpacing.xl) {
                gauge(telemetry.rpm, fallbackRange: 0...8_000, highlightsPeak: true, labelKey: "drive.gauge.rpm")
                gauge(telemetry.speed, fallbackRange: 0...240, highlightsPeak: false, labelKey: "drive.gauge.speed")
            }
            .frame(maxWidth: .infinity)

            ForEach(OBDPIDCategory.allCases, id: \.self) { category in
                let channels = telemetry.channels(in: category).filter { !gaugeChannels.contains($0.request) }
                if !channels.isEmpty {
                    MacOSChannelCategorySection(category: category, channels: channels, isStale: telemetry.isStale)
                }
            }
        }
    }

    private func gauge(
        _ channel: LiveTelemetryChannel?,
        fallbackRange: ClosedRange<Double>,
        highlightsPeak: Bool,
        labelKey: LocalizedStringKey
    ) -> some View {
        let range = channel.flatMap { c in c.minimumValue.flatMap { low in c.maximumValue.map { low...$0 } } } ?? fallbackRange
        let warning: ClosedRange<Double>? = highlightsPeak
            ? (range.lowerBound + (range.upperBound - range.lowerBound) * 0.85)...range.upperBound
            : nil
        return ArcGauge(
            value: channel?.value,
            range: range,
            warningZone: warning,
            valueText: channel?.value.map { Text(verbatim: $0.formatted(.number.precision(.fractionLength(0)))) },
            unit: channel.map { Text(verbatim: $0.unit) },
            label: Text(labelKey),
            unavailableText: Text("drive.live.noValue")
        )
        .frame(maxWidth: 280)
        .opacity(telemetry.isStale ? 0.5 : 1)
        .frame(maxWidth: .infinity)
    }
}
#endif
