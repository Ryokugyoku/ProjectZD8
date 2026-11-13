#if os(macOS)
import SwiftUI

/// 記録中セッションの概要(車両・アダプター・経過・サンプル数・応答率・距離)。
struct MacOSSessionHeaderView: View {
    let summary: ActiveSessionSummary

    var body: some View {
        InsightCard {
            VStack(alignment: .leading, spacing: InsightSpacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: InsightSpacing.sm) {
                    Text(verbatim: summary.vehicleName).font(InsightTypography.screenTitle)
                    if summary.isDemo { StatusBadge(Text("drive.badge.demo"), tone: .warning, symbol: "sparkles") }
                    Spacer()
                    HStack(spacing: InsightSpacing.xs) {
                        Image(systemName: summary.adapterTransport.macOSSymbol).accessibilityHidden(true)
                        Text(verbatim: summary.adapterName)
                    }
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: InsightSpacing.xl) {
                    stat("drive.session.elapsed", Text(verbatim: DriveSessionPresentation.elapsedText(microseconds: summary.elapsedMicroseconds)))
                    stat("drive.session.samples", Text(verbatim: summary.sampleCount.formatted()))
                    stat("drive.session.responseRate", Text(verbatim: DriveSessionPresentation.responseRateText(summary.responseRate)))
                    stat(
                        "drive.session.distance",
                        summary.distanceKilometers.map { Text(verbatim: DriveSessionPresentation.distanceText(kilometers: $0)) }
                    )
                }
            }
        }
    }

    private func stat(_ key: LocalizedStringKey, _ value: Text?) -> some View {
        VStack(alignment: .leading, spacing: InsightSpacing.xxs) {
            Text(key).font(InsightTypography.label).foregroundStyle(.secondary)
            if let value {
                value.font(InsightTypography.metricValueSmall)
            } else {
                Text(verbatim: "—").font(InsightTypography.metricValueSmall).foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("drive.session.distance.unavailable"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
