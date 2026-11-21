#if os(iOS)
import SwiftUI

/// iPhoneのセッション解析の対象車両と開始時刻を示す主カードです。
struct IOSSessionLogAnalysisHero: View {
    /// 表示するセッションです。
    let session: ConnectionSession

    /// 解析対象を接続履歴と同じ主カードで示します。
    ///
    /// 責務: 1件のセッションの車両名と開始時刻をアイコン付きの主カードへ変換します。
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 58, height: 58)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("analysis.eyebrow").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.tint)
                Text(session.vehicle?.name ?? String(localized: "history.vehicle.pending"))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(session.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }
}
#endif
