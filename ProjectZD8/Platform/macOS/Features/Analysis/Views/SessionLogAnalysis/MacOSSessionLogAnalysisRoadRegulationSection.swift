#if os(macOS)
import SwiftUI

/// macOS の解析画面の「ルート」の表示で、走行ルートの直後に置く「交通規制との照合」のカードです。
///
/// 地図は持たず、行を選ぶと画面ルートが段階4の地図とグラフでその区間を示します。
struct MacOSSessionLogAnalysisRoadRegulationSection: View {
    /// 交通規制の照合の表示状態です。
    let state: SessionRoadRegulationReviewState
    /// 現在のウインドウ寸法に対応する表示寸法です。
    let metrics: MacOSAppShellMetrics
    /// 交通規制の照合の型付き操作を送出します(切替・再試行)。
    let send: (SessionRoadRegulationReviewAction) -> Void
    /// 行を選んだことを画面ルートへ伝えます(選択・色分けの切替・スクロールは画面ルートが送出します)。
    let onSelectRow: (SessionRoadRegulationReviewRow) -> Void

    /// 見出しの下に、段階の表示か照合の結果を置き、最後に注意書きと出典を置きます。
    ///
    /// 責務: 結果がある時は注記・まとめ・切替・種類ごとの一覧を、無い時は段階の表示を描き、出典は常に最後に描きます。
    var body: some View {
        MacOSSessionLogAnalysisCard(title: "analysis.road_regulation.title", subtitle: "analysis.road_regulation.subtitle", metrics: metrics) {
            VStack(alignment: .leading, spacing: MacOSRoadRegulationReviewMetrics.sectionSpacing * metrics.scale) {
                if state.status == .loaded {
                    results
                } else {
                    MacOSSessionLogAnalysisRoadRegulationStatus(status: state.status, metrics: metrics) { send(.retryRequested) }
                }
                MacOSSessionLogAnalysisRoadRegulationAttribution(
                    attribution: state.attribution,
                    showsDetails: state.status == .loaded,
                    metrics: metrics
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macos-analysis-road-regulation-section")
    }

    /// 照合の結果(注記・まとめ・切替・種類ごとの一覧)です。
    @ViewBuilder private var results: some View {
        MacOSSessionLogAnalysisRoadRegulationNotices(notices: state.notices, metrics: metrics)
        MacOSSessionLogAnalysisRoadRegulationSummary(summaries: state.summaries, metrics: metrics)
        MacOSSessionLogAnalysisRoadRegulationFilter(selection: state.filter) { send(.filterChanged($0)) }
        ForEach(state.sections) { section in
            MacOSSessionLogAnalysisRoadRegulationKindList(
                section: section,
                selectedRowID: state.selectedRowID,
                metrics: metrics,
                onSelectRow: onSelectRow
            )
        }
    }
}
#endif
