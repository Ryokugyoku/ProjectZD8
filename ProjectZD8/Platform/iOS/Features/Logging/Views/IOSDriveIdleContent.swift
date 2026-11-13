#if os(iOS)
import SwiftUI

/// 待機中の内容です。失敗・直近の終了・既定アダプター・接続ボタンを並べます。
struct IOSDriveIdleContent: View {
    let drive: DriveSessionState
    let devices: DeviceConnectionState
    let live: LiveTelemetryState
    let sendDrive: (DriveSessionAction) -> Void
    let sendLive: (LiveTelemetryAction) -> Void
    let onChooseAdapter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.lg) {
            if let failure = drive.failure {
                InlineBanner(
                    .error,
                    message: Text(LocalizedStringKey(failure.localizationKey)),
                    action: InsightAction(Text("common.dismiss")) { sendDrive(.failureDismissed) }
                )
            }
            if drive.recoveredSessionCount > 0 {
                InlineBanner(
                    .info,
                    message: Text("drive.recovered \(drive.recoveredSessionCount)")
                )
            }
            if let ended = drive.lastEndedSession {
                IOSDriveEndedCard(session: ended, live: live, sendLive: sendLive)
            }
            IOSAdapterCard(state: devices, onChoose: onChooseAdapter)
            connectButton
            Text("drive.idle.hint")
                .font(InsightTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        if let adapter = devices.defaultAdapter {
            Button {
                sendDrive(.connectRequested(adapter))
            } label: {
                Label("drive.connect", systemImage: "bolt.horizontal.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.insightPrimary)
        } else {
            Button(action: onChooseAdapter) {
                Label("drive.connect.chooseFirst", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
            }
            .buttonStyle(.insightPrimary)
        }
    }
}
#endif
