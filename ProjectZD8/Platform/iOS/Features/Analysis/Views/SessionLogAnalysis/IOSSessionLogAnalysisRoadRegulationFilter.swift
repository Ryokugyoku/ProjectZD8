#if os(iOS)
import SwiftUI

/// iPhone の解析の「交通規制との照合」で、一覧に出す区間(確認が必要な区間/すべて)を切り替えます。
struct IOSSessionLogAnalysisRoadRegulationFilter: View {
    /// 選んでいる表示の切替です。
    let filter: SessionRoadRegulationReviewFilter
    /// 表示の切替の選択を送出します。
    let onSelect: (SessionRoadRegulationReviewFilter) -> Void

    /// segmented の切替を描画します。
    ///
    /// 責務: 選択肢を並べ、選ばれた値を状態に直接書かず `onSelect` で送出します。
    var body: some View {
        Picker("analysis.road_regulation.filter.title", selection: selection) {
            ForEach(SessionRoadRegulationReviewFilter.allCases) { item in
                Text(LocalizedStringKey(item.titleKey)).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .tint(.cyan)
        .accessibilityIdentifier("ios-analysis-road-regulation-filter")
    }

    /// 状態の値を読み、選択を送出に変える束縛です。
    private var selection: Binding<SessionRoadRegulationReviewFilter> {
        Binding(get: { filter }, set: { onSelect($0) })
    }
}
#endif
