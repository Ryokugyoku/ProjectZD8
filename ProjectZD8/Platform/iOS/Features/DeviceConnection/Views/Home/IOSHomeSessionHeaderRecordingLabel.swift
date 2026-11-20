#if os(iOS)
import SwiftUI

/// セッション見出しで、記録中であることと記録開始からの経過時間を示す表示です。
struct IOSHomeSessionHeaderRecordingLabel: View {
    /// 記録を開始した時刻です。経過時間の起点にします。
    let startedAt: Date

    /// 記録中の印、記録中の文言、経過時間を横に並べます。
    ///
    /// 責務: 1件の記録開始時刻を、記録中の表示と経過タイマーへ描画します。
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.cyan)
                .frame(width: IOSHomeMetrics.recordingIndicatorSize, height: IOSHomeMetrics.recordingIndicatorSize)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(HomeRecordingStatus.activeKey))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)
                .accessibilityIdentifier("ios-home-recording-status")
            Text(startedAt, style: .timer)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(LocalizedStringKey(HomeRecordingStatus.elapsedKey)))
                .accessibilityValue(Text(startedAt, style: .timer))
        }
        .lineLimit(1)
    }
}
#endif
