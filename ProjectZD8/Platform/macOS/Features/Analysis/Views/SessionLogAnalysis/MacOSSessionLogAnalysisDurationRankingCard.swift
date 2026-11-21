#if os(macOS)
import SwiftUI

/// macOSのセッション解析で数値帯ランキングを推定滞在時間と構成比で示すカードです。
struct MacOSSessionLogAnalysisDurationRankingCard: View {
    /// ランキング見出しのローカライズキーです。
    let title: LocalizedStringKey
    /// 集計方法の説明のローカライズキーです。
    let subtitle: LocalizedStringKey
    /// 滞在時間順の数値帯です。
    let bands: [SessionDurationBand]
    /// 数値帯書式のローカライズキーです。
    let unitKey: String
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 解析画面の文字列整形です。
    private let formatter = SessionLogAnalysisTextFormatter()

    /// 数値帯の順位またはデータ不足を表示します。
    ///
    /// 責務: 1件の時間帯ランキングをmacOS向け順位カードへ変換します。
    var body: some View {
        MacOSSessionLogAnalysisCard(title: title, subtitle: subtitle, metrics: metrics) {
            if bands.isEmpty {
                Text("analysis.overview.ranking_empty").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                    row(index: index, band: band)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 1件の数値帯の順位・範囲・構成比・滞在時間を表示します。
    ///
    /// 責務: 1件の数値帯と順位をランキングの1行へ変換します。
    /// - Parameters:
    ///   - index: 0始まりの順位。
    ///   - band: 表示する数値帯。
    /// - Returns: ランキングの1行。
    private func row(index: Int, band: SessionDurationBand) -> some View {
        HStack {
            Text("\(index + 1)")
                .font(.system(size: 15 * metrics.scale, weight: .bold, design: .monospaced))
                .foregroundStyle(.tint)
                .frame(width: 28 * metrics.scale)
            VStack(alignment: .leading, spacing: 2 * metrics.scale) {
                Text(formatter.bandText(band, key: unitKey)).font(.system(size: 12 * metrics.scale, weight: .semibold))
                Text(band.proportion, format: .percent.precision(.fractionLength(0))).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatter.durationText(band.duration)).font(.system(size: 12 * metrics.scale, design: .monospaced))
        }
    }
}
#endif
