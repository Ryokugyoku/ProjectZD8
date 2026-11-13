#if os(macOS)
import SwiftUI

/// ウインドウツールバーの接続状態表示と、接続 / 停止の主操作。全遷移先で共通。
struct MacOSConnectionToolbarContent: ToolbarContent {
    let drive: DriveSessionState
    let onConnect: () -> Void
    let onStop: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            status
        }
        ToolbarItem(placement: .primaryAction) {
            if drive.phase.isIdle {
                Button(action: onConnect) {
                    Label("drive.connect", systemImage: "bolt.horizontal.fill")
                }
                .help(Text("drive.connect.help"))
            } else {
                Button(action: onStop) {
                    Label("drive.stop", systemImage: "stop.fill")
                }
                .disabled(drive.phase == .stopping)
                .help(Text("drive.stop.help"))
            }
        }
    }

    private var status: some View {
        HStack(spacing: InsightSpacing.sm) {
            if let summary = drive.activeSession, drive.phase == .recording {
                MacOSRecordingIndicator()
                Text(verbatim: DriveSessionPresentation.elapsedText(microseconds: summary.elapsedMicroseconds))
                    .font(InsightTypography.numeric(.footnote, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(verbatim: summary.vehicleName)
                    .font(InsightTypography.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(LocalizedStringKey(drive.phase.localizationKey))
                    .font(InsightTypography.footnote)
                    .foregroundStyle(.secondary)
                if let adapter = drive.adapter {
                    Text(verbatim: adapter.displayName)
                        .font(InsightTypography.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
