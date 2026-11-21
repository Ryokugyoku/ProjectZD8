#if os(iOS)
import SwiftUI

/// 履歴総数と記録済み総走行時間を示す、履歴一覧の上部カードです。
struct IOSConnectionHistoryHeroCard: View {
    /// 表示する履歴の総数です。
    let sessionCount: Int
    /// 終了済みセッションの記録済み総走行時間です。
    let totalRecordedDuration: TimeInterval

    /// 総走行時間を整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()

    /// 画面の見出しと集計値のピルを描画します。
    ///
    /// 責務: 履歴の総数と総走行時間を、見出し付きの上部カードへ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("history.eyebrow").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.tint)
                    Text("history.title").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("history.subtitle").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                IOSConnectionHistorySummaryPill(value: "\(sessionCount)", titleKey: "history.summary.total", color: .primary)
                IOSConnectionHistorySummaryPill(
                    value: measurementFormatter.durationText(totalRecordedDuration),
                    titleKey: "history.summary.duration",
                    color: .cyan
                )
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }
}
#endif
