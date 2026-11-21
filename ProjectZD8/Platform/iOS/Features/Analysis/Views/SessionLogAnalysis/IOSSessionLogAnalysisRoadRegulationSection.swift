#if os(iOS)
import SwiftUI

/// iPhone の解析画面の「ルート」の表示で、走行ルートと交通規制データの照合の結果をカードとして描画します。
struct IOSSessionLogAnalysisRoadRegulationSection: View {
    /// 交通規制の照合の表示状態です。
    let state: SessionRoadRegulationReviewState
    /// 一覧の表示の切替の選択を送出します。
    let onFilterChanged: (SessionRoadRegulationReviewFilter) -> Void
    /// 一覧の行の選択を送出します。
    let onRowSelected: (SessionRoadRegulationReviewRow) -> Void
    /// 照合の再試行の要求を送出します。
    let onRetry: () -> Void

    /// 照合の段階に応じた中身と、最後に出典と注意書きを持つカードを描画します。
    ///
    /// 責務: 結果が出ていれば注記・まとめ・切替・種類ごとの一覧を、出ていなければ段階の表示を置き、出典と注意書きを常に最後に置きます。
    var body: some View {
        IOSSessionLogAnalysisCard(title: "analysis.road_regulation.title", subtitle: "analysis.road_regulation.subtitle") {
            VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.sectionSpacing) {
                if state.status == .loaded {
                    loaded
                } else {
                    IOSSessionLogAnalysisRoadRegulationStatus(status: state.status, onRetry: onRetry)
                }
                IOSSessionLogAnalysisRoadRegulationAttribution(attribution: state.attribution, showsSource: state.status == .loaded)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ios-analysis-road-regulation-section")
    }

    /// 照合の結果が出た時の中身です。
    ///
    /// 責務: 注記・まとめ・表示の切替・種類ごとの一覧を縦に並べます。
    private var loaded: some View {
        VStack(alignment: .leading, spacing: IOSRoadRegulationReviewMetrics.sectionSpacing) {
            IOSSessionLogAnalysisRoadRegulationNotices(notices: state.notices)
            IOSSessionLogAnalysisRoadRegulationSummary(summaries: state.summaries)
            IOSSessionLogAnalysisRoadRegulationFilter(filter: state.filter, onSelect: onFilterChanged)
            ForEach(state.sections) { section in
                IOSSessionLogAnalysisRoadRegulationKindList(section: section, selectedRowID: state.selectedRowID, onSelect: onRowSelected)
            }
        }
    }
}
#endif
