#if os(macOS)
import SwiftUI

/// macOSのセッション解析の対象車両、開始時刻、Rawログ件数を示す主カードです。
struct MacOSSessionLogAnalysisHero: View {
    /// 表示するセッションです。
    let session: ConnectionSession
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 解析対象とRawログ件数を接続履歴と同じ主カードで示します。
    ///
    /// 責務: 1件のセッションの車両名・開始時刻・Rawログ件数をアイコン付きの主カードへ変換します。
    var body: some View {
        HStack(spacing: 20 * metrics.scale) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 31 * metrics.scale, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 76 * metrics.scale, height: 76 * metrics.scale)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))
            VStack(alignment: .leading, spacing: 5 * metrics.scale) {
                Text("analysis.eyebrow")
                    .font(.system(size: 10 * metrics.scale, weight: .bold, design: .rounded))
                    .tracking(1.8 * metrics.scale)
                    .foregroundStyle(.tint)
                Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending"))
                    .font(.system(size: 30 * metrics.scale, weight: .bold, design: .rounded))
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.system(size: 12 * metrics.scale, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4 * metrics.scale) {
                Text(session.rawLogSummary.recordCount, format: .number)
                    .font(.system(size: 24 * metrics.scale, weight: .bold, design: .rounded))
                Text("analysis.summary.samples")
                    .font(.system(size: 10 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24 * metrics.scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }
}
#endif
