#if os(macOS)
import SwiftUI

/// macOS の「交通規制との照合」のカードの最後に置く、注意書きと出典です。
///
/// 注意書きは段階に関係なく常に出し、使用したデータ・出典・加工の表記・利用日・配布ページは照合の結果がある時だけ出します。
struct MacOSSessionLogAnalysisRoadRegulationAttribution: View {
    /// 出典の表示内容です。
    let attribution: SessionRoadRegulationReviewAttribution
    /// 使用したデータ・出典・加工の表記・利用日・配布ページを出す時に `true` です。
    let showsDetails: Bool
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics

    /// 注意書きと出典を縦に並べます。
    ///
    /// 責務: 注意書きを描き、`showsDetails` の時だけ使用したデータ以降を順に描きます。
    var body: some View {
        VStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.attributionSpacing * metrics.scale) {
            disclaimer
            if showsDetails {
                details
            }
        }
        .font(.system(size: MacOSRoadRegulationReviewMetrics.captionFontSize * metrics.scale))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-analysis-road-regulation-attribution")
    }

    /// 判定が目安で、違反を断定しない旨の注意書きです。アイコンだけをオレンジで小さく強調します。
    private var disclaimer: some View {
        Label {
            Text(LocalizedStringKey(SessionRoadRegulationReviewAttribution.disclaimerKey))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
        }
    }

    /// 使用したデータ・出典・加工の表記・利用日・配布ページです。
    @ViewBuilder private var details: some View {
        if !attribution.datasetTexts.isEmpty {
            Text(LocalizedStringKey(SessionRoadRegulationReviewAttribution.datasetsTitleKey))
                .fontWeight(.semibold)
            ForEach(Array(attribution.datasetTexts.enumerated()), id: \.offset) { _, text in
                Text(verbatim: text)
            }
        }
        Text(LocalizedStringKey(SessionRoadRegulationReviewAttribution.sourceKey))
            .fixedSize(horizontal: false, vertical: true)
        Text(LocalizedStringKey(SessionRoadRegulationReviewAttribution.processedKey))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if let usedOnText = attribution.usedOnText {
            Text(verbatim: usedOnText)
                .foregroundStyle(.secondary)
        }
        if let sourceURL = attribution.sourceURL {
            Link(destination: sourceURL) {
                Text(verbatim: sourceURL.absoluteString)
            }
            .accessibilityIdentifier("macos-analysis-road-regulation-source-link")
        }
    }
}
#endif
