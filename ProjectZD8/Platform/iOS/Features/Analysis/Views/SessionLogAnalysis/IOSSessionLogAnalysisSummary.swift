#if os(iOS)
import SwiftUI

/// iPhoneのセッション解析で読込済み・数値化済み・Raw保持の件数を並べる集計列です。
struct IOSSessionLogAnalysisSummary: View {
    /// 読込済みの時系列件数です。
    let sampleCount: Int
    /// 数値化できた件数です。
    let decodedCount: Int
    /// Rawのまま保持した件数です。
    let rawOnlyCount: Int

    /// 3件の集計を同じ幅のカードで横に並べます。
    ///
    /// 責務: 3種類の件数をアイコン付きの集計カード列へ変換します。
    var body: some View {
        HStack(spacing: 8) {
            metric(value: sampleCount, key: "analysis.summary.samples", symbol: "waveform.path.ecg", color: .cyan)
            metric(value: decodedCount, key: "analysis.summary.decoded", symbol: "function", color: .green)
            metric(value: rawOnlyCount, key: "analysis.summary.raw", symbol: "shippingbox", color: .orange)
        }
    }

    /// 1件の解析集計をコンパクトなカードへ変換します。
    ///
    /// 責務: 1件の解析件数をアイコンと見出しを持つiPhoneカードへ変換します。
    /// - Parameters:
    ///   - value: 表示する件数。
    ///   - key: 集計見出しのローカライズキー。
    ///   - symbol: 集計概念を示すSF Symbol。
    ///   - color: 集計カードのアクセント色。
    /// - Returns: 同じ幅で並べられる集計カード。
    private func metric(value: Int, key: LocalizedStringKey, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value, format: .number).font(.headline.weight(.bold))
            Text(key).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
#endif
