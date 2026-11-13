#if os(iOS)
import SwiftUI

/// 回転数と車速の主要ゲージです。値が無い・収集対象外の場合は欠損として示します。
struct IOSDriveGauges: View {
    let live: LiveTelemetryState

    var body: some View {
        HStack(alignment: .top, spacing: InsightSpacing.md) {
            gauge(live.rpm, range: IOSAppShellMetrics.rpmRange, warning: IOSAppShellMetrics.rpmWarningZone, label: "drive.gauge.rpm", unit: "rpm")
            gauge(live.speed, range: IOSAppShellMetrics.speedRange, warning: nil, label: "drive.gauge.speed", unit: "km/h")
        }
        .frame(maxWidth: .infinity)
        .opacity(live.isStale ? 0.5 : 1)
    }

    private func gauge(
        _ channel: LiveTelemetryChannel?,
        range: ClosedRange<Double>,
        warning: ClosedRange<Double>?,
        label: LocalizedStringKey,
        unit: String
    ) -> some View {
        ArcGauge(
            value: channel?.value,
            range: range,
            warningZone: warning,
            valueText: channel?.value.map { Text($0, format: .number.precision(.fractionLength(0))) },
            unit: Text(verbatim: unit),
            label: Text(label),
            unavailableText: Text(channel == nil ? LocalizedStringKey("drive.gauge.notCollected") : LocalizedStringKey("common.unavailable")),
            lineWidth: IOSAppShellMetrics.gaugeLineWidth
        )
        .frame(maxWidth: IOSAppShellMetrics.gaugeSide)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}
#endif
