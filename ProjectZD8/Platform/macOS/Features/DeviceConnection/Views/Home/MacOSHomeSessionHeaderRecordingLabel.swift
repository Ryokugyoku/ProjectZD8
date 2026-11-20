#if os(macOS)
import SwiftUI

/// セッション見出しで、記録中であることと記録開始からの経過時間を示す表示です。
struct MacOSHomeSessionHeaderRecordingLabel: View {
    /// 記録を開始した時刻です。経過時間の起点にします。
    let startedAt: Date
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 記録中の印、記録中の文言、経過時間を横に並べます。
    ///
    /// 責務: 1件の記録開始時刻を、記録中の表示と経過タイマーへ描画します。
    var body: some View {
        HStack(spacing: 9 * scale) {
            Circle()
                .fill(Color.cyan)
                .frame(width: 9 * scale, height: 9 * scale)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(HomeRecordingStatus.activeKey))
                .font(.system(size: 12 * scale, weight: .bold))
                .foregroundStyle(.cyan)
                .accessibilityIdentifier("macos-home-recording-status")
            Text(startedAt, style: .timer)
                .font(.system(size: 20 * scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(LocalizedStringKey(HomeRecordingStatus.elapsedKey)))
                .accessibilityValue(Text(startedAt, style: .timer))
        }
        .lineLimit(1)
    }
}
#endif
