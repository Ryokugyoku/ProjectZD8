#if os(macOS)
import SwiftUI

/// macOSのセッション解析で読込済み・数値化済み・Raw保持の件数を並べる集計列です。
struct MacOSSessionLogAnalysisSummary: View {
    /// 読込済みの時系列件数です。
    let sampleCount: Int
    /// 数値化できた件数です。
    let decodedCount: Int
    /// Rawのまま保持した件数です。
    let rawOnlyCount: Int
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 3件の集計を同じ幅のカードで横に並べます。
    ///
    /// 責務: 3種類の件数をアイコン付きの集計カード列へ変換します。
    var body: some View {
        HStack(spacing: 12 * metrics.scale) {
            metric(sampleCount, key: "analysis.summary.samples", symbol: "waveform.path.ecg", color: .cyan)
            metric(decodedCount, key: "analysis.summary.decoded", symbol: "function", color: .green)
            metric(rawOnlyCount, key: "analysis.summary.raw", symbol: "shippingbox", color: .orange)
        }
    }

    /// 1件の解析集計をカードへ変換します。
    ///
    /// 責務: 1件の解析件数をアイコンと見出しを持つmacOSカードへ変換します。
    /// - Parameters:
    ///   - value: 表示する件数。
    ///   - key: 集計見出しのローカライズキー。
    ///   - symbol: 集計概念を示すSF Symbol。
    ///   - color: 集計カードのアクセント色。
    /// - Returns: 同じ幅で並べられる集計カード。
    private func metric(_ value: Int, key: LocalizedStringKey, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8 * metrics.scale) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value.formatted()).font(.system(size: 24 * metrics.scale, weight: .bold, design: .rounded))
            Text(key).font(.system(size: 11 * metrics.scale)).foregroundStyle(.secondary)
        }
        .padding(17 * metrics.scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20 * metrics.scale, style: .continuous))
    }
}
#endif
