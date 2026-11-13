#if os(iOS)
import SwiftUI

/// 記録中セッションの要約カードです。車両・アダプター・経過・件数・応答率・距離を示します。
struct IOSDriveSessionHeader: View {
    let summary: ActiveSessionSummary
    let onStop: () -> Void

    var body: some View {
        InsightCard(
            title: Text(verbatim: summary.vehicleName),
            trailing: {
                HStack(spacing: InsightSpacing.xs) {
                    if summary.isDemo { StatusBadge(Text("drive.demo"), tone: .warning) }
                    StatusBadge(Text("drive.phase.recording"), tone: .active, symbol: "record.circle")
                }
            },
            content: {
                Label {
                    Text(verbatim: summary.adapterName)
                } icon: {
                    Image(systemName: summary.adapterTransport.iosSymbolName)
                }
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: InsightSpacing.xl, verticalSpacing: InsightSpacing.md) {
                    GridRow {
                        stat("drive.header.elapsed", Text(verbatim: DriveSessionPresentation.elapsedText(microseconds: summary.elapsedMicroseconds)))
                        stat("drive.header.samples", Text(summary.sampleCount, format: .number))
                    }
                    GridRow {
                        stat("drive.header.responseRate", Text(verbatim: DriveSessionPresentation.responseRateText(summary.responseRate)))
                        stat("drive.header.distance", summary.distanceKilometers.map { Text(verbatim: DriveSessionPresentation.distanceText(kilometers: $0)) })
                    }
                }
                LinearMeter(value: summary.responseRate, label: Text("drive.header.responseRate"), valueText: Text(verbatim: DriveSessionPresentation.responseRateText(summary.responseRate)))
                Button(action: onStop) {
                    Label("drive.stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.insightDestructive)
                .accessibilityHint(Text("drive.stop.hint"))
            }
        )
    }

    /// 項目名と値の組です。値が無ければ欠損として「—」を示します。
    private func stat(_ key: LocalizedStringKey, _ value: Text?) -> some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
            Text(key).font(InsightTypography.footnote).foregroundStyle(.secondary)
            if let value {
                value.font(InsightTypography.metricValue)
            } else {
                Text(verbatim: "—").font(InsightTypography.metricValue).foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("common.unavailable"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
