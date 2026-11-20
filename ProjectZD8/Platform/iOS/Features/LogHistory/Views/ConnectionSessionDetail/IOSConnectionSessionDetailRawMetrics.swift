#if os(iOS)
import SwiftUI

/// iPhone のセッション詳細で、Raw ログの件数・容量・時刻精度を横に並べて表示します。
struct IOSConnectionSessionDetailRawMetrics: View {
    /// Raw ログの記録件数の表示文字列です。
    let recordCountText: String
    /// Raw ログの容量の表示文字列です。
    let byteCountText: String

    /// 3つの集計カードを等幅で描画します。
    ///
    /// 責務: 件数・容量・時刻精度を、それぞれの見出しと色を持つカードとして並べます。
    var body: some View {
        HStack(spacing: 10) {
            metric(value: recordCountText, titleKey: "history.raw.records", systemImage: "number", color: .cyan)
            metric(value: byteCountText, titleKey: "history.raw.bytes", systemImage: "externaldrive.fill", color: .blue)
            metric(value: "ms", titleKey: "history.raw.precision", systemImage: "timer", color: .indigo)
        }
    }

    /// 1件の Raw ログ集計値をコンパクトなカードとして描画します。
    ///
    /// 責務: 1件の集計値をアイコン、値、見出しを持つ iPhone カードへ変換します。
    /// - Parameters:
    ///   - value: 強調表示する集計値。
    ///   - titleKey: ローカライズ済み見出しキー。
    ///   - systemImage: 集計概念を示す SF Symbol。
    ///   - color: 集計カードのアクセント色。
    /// - Returns: 固定幅を共有する集計カード。
    private func metric(value: String, titleKey: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(titleKey).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(color.opacity(0.16)) }
    }
}
#endif
