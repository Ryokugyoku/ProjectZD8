#if os(iOS)
import SwiftUI

/// 直近に終了したセッションの終了理由と、残っている古い値の扱いを示すカードです。
struct IOSDriveEndedCard: View {
    let session: DriveSession
    let live: LiveTelemetryState
    let sendLive: (LiveTelemetryAction) -> Void

    var body: some View {
        InsightCard(
            title: Text("drive.ended.title"),
            trailing: {
                if session.isDemo { StatusBadge(Text("drive.demo"), tone: .warning) }
            },
            content: {
                if let reason = session.endReason {
                    Label {
                        Text(LocalizedStringKey(DriveSessionPresentation.endReasonKey(reason)))
                    } icon: {
                        Image(systemName: session.wasInterrupted ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(session.wasInterrupted ? InsightPalette.warning : InsightPalette.positive)
                    }
                    .font(InsightTypography.body)
                }
                HStack(spacing: InsightSpacing.xl) {
                    VStack(alignment: .leading) {
                        Text("drive.header.samples").font(InsightTypography.footnote).foregroundStyle(.secondary)
                        Text(session.sampleCount, format: .number).font(InsightTypography.metricValueSmall)
                    }
                    if let duration = session.duration {
                        VStack(alignment: .leading) {
                            Text("drive.header.elapsed").font(InsightTypography.footnote).foregroundStyle(.secondary)
                            Text(verbatim: LogHistorySessionRow.durationText(duration))
                                .font(InsightTypography.metricValueSmall)
                        }
                    }
                }
                if live.isStale {
                    Button { sendLive(.clearRequested) } label: { Text("drive.ended.clear").frame(maxWidth: .infinity) }
                        .buttonStyle(.insightSecondary)
                    IOSLiveChannelSections(live: live)
                }
            }
        )
    }
}
#endif
