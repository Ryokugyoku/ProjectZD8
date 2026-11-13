#if os(iOS)
import SwiftUI

/// 記録中であることをどのタブからでも示す、コンパクトなインジケーターです。
struct IOSRecordingIndicator: View {
    let summary: ActiveSessionSummary
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: InsightSpacing.sm) {
                Circle()
                    .fill(InsightPalette.critical)
                    .frame(width: IOSAppShellMetrics.recordingDotSize, height: IOSAppShellMetrics.recordingDotSize)
                    .opacity(isPulsing ? 0.35 : 1)
                    .accessibilityHidden(true)
                Text("shell.recording.label")
                    .font(InsightTypography.label)
                Text(verbatim: summary.vehicleName)
                    .font(InsightTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: InsightSpacing.sm)
                Text(verbatim: DriveSessionPresentation.elapsedText(microseconds: summary.elapsedMicroseconds))
                    .font(InsightTypography.numeric(.footnote, weight: .medium))
            }
            .padding(.horizontal, InsightSpacing.lg)
            .frame(minHeight: InsightSpacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("shell.recording.hint"))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isPulsing = true }
        }
    }
}
#endif
