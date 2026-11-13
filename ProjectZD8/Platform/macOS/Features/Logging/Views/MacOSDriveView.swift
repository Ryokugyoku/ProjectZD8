#if os(macOS)
import SwiftUI

/// ドライブ画面。接続前の待機・進行・記録中ダッシュボード・終了後の状態を切り替える。
struct MacOSDriveView: View {
    let deviceConnection: DeviceConnectionState
    let drive: DriveSessionState
    let telemetry: LiveTelemetryState
    let onConnect: () -> Void
    let onChooseAdapter: () -> Void
    let sendDrive: (DriveSessionAction) -> Void
    let sendTelemetry: (LiveTelemetryAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: InsightSpacing.xl) {
                if let failure = drive.failure {
                    InlineBanner(
                        .error,
                        message: Text(LocalizedStringKey(failure.localizationKey)),
                        action: InsightAction(Text("common.dismiss")) { sendDrive(.failureDismissed) }
                    )
                }
                if drive.recoveredSessionCount > 0 {
                    InlineBanner(.info, message: Text("drive.recovered \(drive.recoveredSessionCount)"))
                }
                content
            }
            .padding(MacOSAppShellMetrics.contentPadding)
            .frame(maxWidth: MacOSAppShellMetrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(InsightBackground())
        .navigationTitle(Text("shell.destination.drive"))
    }

    @ViewBuilder
    private var content: some View {
        if let summary = drive.activeSession {
            MacOSSessionHeaderView(summary: summary)
            MacOSLiveDashboardView(telemetry: telemetry)
        } else if drive.phase.isIdle {
            idleContent
        } else {
            MacOSDriveProgressView(phase: drive.phase, adapter: drive.adapter)
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        if case .stale(let reason) = telemetry.status {
            MacOSDriveStaleBanner(reason: reason) { sendTelemetry(.clearRequested) }
            MacOSLiveDashboardView(telemetry: telemetry)
        } else {
            VStack(alignment: .leading, spacing: InsightSpacing.lg) {
                MacOSDefaultAdapterCard(state: deviceConnection, onChooseAdapter: onChooseAdapter)
                HStack {
                    Button(action: onConnect) {
                        Label("drive.connect", systemImage: "bolt.horizontal.fill")
                    }
                    .buttonStyle(.insightPrimary)
                    .keyboardShortcut(.defaultAction)
                    Text(deviceConnection.defaultAdapter == nil ? "drive.connect.hintNoAdapter" : "drive.connect.hint")
                        .font(InsightTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
        }
    }
}
#endif
