#if os(iOS)
import SwiftUI

/// 記録中のダッシュボードです。セッション要約・主要ゲージ・分類別のチャンネルを並べます。
struct IOSDriveRecordingContent: View {
    let drive: DriveSessionState
    let live: LiveTelemetryState
    let sendDrive: (DriveSessionAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.lg) {
            if let failure = drive.failure {
                InlineBanner(
                    .error,
                    message: Text(LocalizedStringKey(failure.localizationKey)),
                    action: InsightAction(Text("common.dismiss")) { sendDrive(.failureDismissed) }
                )
            }
            if let summary = drive.activeSession {
                IOSDriveSessionHeader(summary: summary, onStop: { sendDrive(.stopRequested) })
            }
            IOSDriveGauges(live: live)
            IOSLiveChannelSections(live: live)
        }
    }
}
#endif
