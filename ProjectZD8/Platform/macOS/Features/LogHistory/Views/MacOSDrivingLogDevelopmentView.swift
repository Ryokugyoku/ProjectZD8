#if os(macOS)
import SwiftUI

/// 選択セッションの走行ログ機能が開発中であることをmacOS向けに表示します。
struct MacOSDrivingLogDevelopmentView: View {
    /// 将来の走行ログ取得対象となる接続セッションです。
    let session: ConnectionSession
    /// 現在のウインドウサイズに対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 選択済みセッションを識別できる開発中画面を提供します。
    ///
    /// 責務: 1件の選択セッションに対する未実装の走行ログ詳細を明示します。
    var body: some View {
        VStack(spacing: 20 * metrics.scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 48 * metrics.scale, weight: .medium))
                    .foregroundStyle(.tint)
            }
            .frame(width: 126 * metrics.scale, height: 126 * metrics.scale)

            Text("history.detail.development.badge")
                .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                .tracking(1.6 * metrics.scale)
                .foregroundStyle(.tint)

            Text("history.detail.development.title")
                .font(.system(size: 28 * metrics.scale, weight: .bold, design: .rounded))

            Text("history.detail.development.body")
                .font(.system(size: 14 * metrics.scale))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460 * metrics.scale)

            Text(session.id.rawValue.uuidString.uppercased())
                .font(.system(size: 10 * metrics.scale, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(36 * metrics.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("macos-driving-log-development")
    }
}
#endif
