#if os(macOS)
import SwiftUI

/// 記録中を示す小さな点と文言。色だけに頼らずテキストを併記する。
struct MacOSRecordingIndicator: View {
    var body: some View {
        HStack(spacing: InsightSpacing.xs) {
            Circle()
                .fill(InsightPalette.critical)
                .frame(width: MacOSAppShellMetrics.recordingDotSize, height: MacOSAppShellMetrics.recordingDotSize)
                .accessibilityHidden(true)
            Text("shell.recording")
                .font(InsightTypography.footnote)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
