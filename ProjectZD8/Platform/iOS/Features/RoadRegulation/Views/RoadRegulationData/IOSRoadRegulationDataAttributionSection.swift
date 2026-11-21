#if os(iOS)
import SwiftUI

/// iOSの交通規制データの管理画面で、出典・利用日・「加工して作成」・データの注意書きを描画します。
///
/// 出典と注意書きは取得の有無にかかわらず常に出します(提供元や国が作成したかのように見せないため)。
struct IOSRoadRegulationDataAttributionSection: View {
    /// 出典の表示です。
    let attribution: RoadRegulationAttribution
    /// 利用日の文言です。取得済みが無ければ `nil`。
    let usedOnText: String?

    /// 出典と注意書きを縦に並べた欄を提供します。
    ///
    /// 責務: 出典・配布ページへのリンク・利用日・加工の表記・注意書きを順に描画します。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSRoadRegulationDataMetrics.attributionSpacing) {
            Text(LocalizedStringKey(RoadRegulationAttribution.sourceKey))
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: RoadRegulationAttribution.sourceURLString) {
                Link(destination: url) {
                    Text(verbatim: RoadRegulationAttribution.sourceURLString)
                }
                .accessibilityIdentifier("ios-road-regulation-source-link")
            }
            if let usedOnText {
                Text(verbatim: usedOnText)
                    .foregroundStyle(.secondary)
            }
            Text(LocalizedStringKey(RoadRegulationAttribution.processedKey))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            disclaimer
        }
        .font(.footnote)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-road-regulation-attribution")
    }

    /// データが実際の規制と一致しないことがある旨の注意書きです。アイコンだけをオレンジで強調します。
    private var disclaimer: some View {
        Label {
            Text(LocalizedStringKey(RoadRegulationAttribution.disclaimerKey))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
        }
        .accessibilityIdentifier("ios-road-regulation-disclaimer")
    }
}
#endif
