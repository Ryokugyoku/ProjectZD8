#if os(iOS)
import SwiftUI

/// 選択セッションの走行ログ機能が開発中であることをiPhone向けに表示します。
struct IOSDrivingLogDevelopmentView: View {
    /// 将来の走行ログ取得対象となる接続セッションです。
    let session: ConnectionSession

    /// 選択済みセッションを識別できる開発中画面を提供します。
    ///
    /// 責務: 1件の選択セッションに対する未実装の走行ログ詳細を明示します。
    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.13))
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.tint)
            }
            .frame(width: 104, height: 104)

            Text("history.detail.development.badge")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.tint)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.10), in: Capsule())

            VStack(spacing: 9) {
                Text("history.detail.development.title")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("history.detail.development.body")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(session.id.rawValue.uuidString.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("history.detail.title")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios-driving-log-development")
    }
}
#endif
