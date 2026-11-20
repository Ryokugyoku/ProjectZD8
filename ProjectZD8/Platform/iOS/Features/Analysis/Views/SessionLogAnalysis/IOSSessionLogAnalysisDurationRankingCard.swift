#if os(iOS)
import SwiftUI

/// iPhoneのセッション解析で数値帯ランキングを推定滞在時間と構成比で示すカードです。
struct IOSSessionLogAnalysisDurationRankingCard: View {
    /// ランキング見出しのローカライズキーです。
    let title: LocalizedStringKey
    /// 集計方法の説明のローカライズキーです。
    let subtitle: LocalizedStringKey
    /// 滞在時間順の数値帯です。
    let bands: [SessionDurationBand]
    /// 数値帯書式のローカライズキーです。
    let unitKey: String
    /// 解析画面の文字列整形です。
    private let formatter = SessionLogAnalysisTextFormatter()

    /// 数値帯の順位またはデータ不足を表示します。
    ///
    /// 責務: 1件の時間帯ランキングをiPhone向け順位カードへ変換します。
    var body: some View {
        IOSSessionLogAnalysisCard(title: title, subtitle: subtitle) {
            if bands.isEmpty {
                Text("analysis.overview.ranking_empty").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                    HStack {
                        Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.tint).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatter.bandText(band, key: unitKey)).font(.subheadline.weight(.semibold))
                            Text(band.proportion, format: .percent.precision(.fractionLength(0))).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatter.durationText(band.duration)).font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
    }
}
#endif
