#if os(iOS)
import SwiftUI

/// 全応答値へ分類単位で到達できる一覧です。各分類は詳細画面へ遷移します。
struct IOSLiveTelemetryPanelCategoryList: View {
    /// 分類と代表値の計算に使うサンプルのまとまりです。
    let groups: LiveTelemetrySampleGroups

    /// 応答のある分類を遷移カードとして並べます。
    ///
    /// 責務: 応答のある分類ごとに、分類カードと詳細画面への遷移を結び付けます。
    var body: some View {
        VStack(alignment: .leading, spacing: IOSLiveTelemetryPanelMetrics.sectionContentSpacing) {
            IOSLiveTelemetryPanelSectionHeader(titleKey: "telemetry.section.all", symbol: "square.grid.2x2")
            ForEach(groups.availableCategories, id: \.self) { category in
                NavigationLink {
                    IOSLiveTelemetryPanelCategoryDetail(category: category, samples: groups.samples(in: category))
                } label: {
                    IOSLiveTelemetryPanelCategoryCard(
                        category: category,
                        count: groups.samples(in: category).count,
                        representative: groups.representativeSample(in: category)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
#endif
