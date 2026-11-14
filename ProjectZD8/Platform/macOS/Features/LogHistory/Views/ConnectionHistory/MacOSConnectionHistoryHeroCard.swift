#if os(macOS)
import SwiftUI

/// 履歴総数と記録済み総走行時間を示す接続履歴の画面上部カードです。
struct MacOSConnectionHistoryHeroCard: View {
    /// 履歴内の全セッション数です。
    let sessionCount: Int
    /// 記録済みセッションの総走行時間です。
    let totalRecordedDuration: TimeInterval
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 走行時間を表示用文字列へ整形します。
    private let measurementFormatter = ConnectionHistoryMeasurementFormatter()

    /// アイコン、見出し、総数、総時間を横一列に描画します。
    ///
    /// 責務: 履歴全体の集計値を画面上部カードへ配置します。
    var body: some View {
        HStack(spacing: 20 * scale) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 31 * scale, weight: .semibold)).foregroundStyle(.tint)
                .frame(width: 76 * scale, height: 76 * scale)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
            VStack(alignment: .leading, spacing: 5 * scale) {
                Text("history.eyebrow")
                    .font(.system(size: 10 * scale, weight: .bold, design: .rounded)).tracking(1.8 * scale).foregroundStyle(.tint)
                Text("history.title").font(.system(size: 30 * scale, weight: .bold, design: .rounded))
                Text("history.subtitle").font(.system(size: 13 * scale, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12 * scale)
            MacOSConnectionHistorySummaryValue(
                value: "\(sessionCount)",
                titleKey: "history.summary.total",
                color: .primary,
                scale: scale
            )
            MacOSConnectionHistorySummaryValue(
                value: measurementFormatter.durationText(totalRecordedDuration),
                titleKey: "history.summary.duration",
                color: .cyan,
                scale: scale
            )
        }
        .padding(24 * scale)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26 * scale, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26 * scale, style: .continuous).stroke(Color.primary.opacity(0.08)) }
    }
}
#endif
