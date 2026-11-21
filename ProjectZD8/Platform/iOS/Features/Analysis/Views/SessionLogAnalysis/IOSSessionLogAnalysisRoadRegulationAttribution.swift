#if os(iOS)
import SwiftUI

/// iPhone の解析の「交通規制との照合」の最後に、注意書きと出典(使用したデータ・出典・加工の表記・利用日・配布ページ)を描画します。
///
/// 注意書きは照合の段階に関係なく常に出します。出典の項目は照合の結果が出た時だけ出します。
struct IOSSessionLogAnalysisRoadRegulationAttribution: View {
    /// 出典の表示内容(解決済みの文字と配布ページ)です。
    let attribution: SessionRoadRegulationReviewAttribution
    /// 照合の結果が出ている時に `true` です。`false` の時は注意書きだけを出します。
    let showsSource: Bool

    /// 注意書きと出典を縦に並べます。
    ///
    /// 責務: 注意書きを置き、結果が出ている時だけ使用したデータ・出典・加工の表記・利用日・配布ページへのリンクを続けます。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.attributionSpacing) {
            disclaimer
            if showsSource {
                datasets
                Text(LocalizedStringKey(SessionRoadRegulationReviewAttribution.sourceKey))
                    .fixedSize(horizontal: false, vertical: true)
                Text(LocalizedStringKey(SessionRoadRegulationReviewAttribution.processedKey))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let usedOnText = attribution.usedOnText {
                    Text(verbatim: usedOnText)
                        .foregroundStyle(.secondary)
                }
                if let url = attribution.sourceURL {
                    Link(destination: url) {
                        Text(verbatim: url.absoluteString)
                    }
                    .tint(.cyan)
                }
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-analysis-road-regulation-attribution")
    }

    /// データが実際の規制と一致しないことがあり、判定は目安である旨の注意書きです。アイコンだけをオレンジで小さく強調します。
    private var disclaimer: some View {
        Label {
            Text(LocalizedStringKey(SessionRoadRegulationReviewAttribution.disclaimerKey))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
        }
    }

    /// 使用したデータ(版ごとの県と基準月)の見出しと行です。版が無ければ何も描きません。
    @ViewBuilder private var datasets: some View {
        if !attribution.datasetTexts.isEmpty {
            Text(LocalizedStringKey(SessionRoadRegulationReviewAttribution.datasetsTitleKey))
                .fontWeight(.semibold)
            ForEach(Array(attribution.datasetTexts.enumerated()), id: \.offset) { _, text in
                Text(verbatim: text)
            }
        }
    }
}
#endif
