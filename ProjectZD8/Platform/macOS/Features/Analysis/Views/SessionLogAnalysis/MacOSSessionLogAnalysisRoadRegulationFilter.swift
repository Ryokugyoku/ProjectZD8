#if os(macOS)
import SwiftUI

/// macOS の「交通規制との照合」のカードで、一覧に出す区間(確認が必要な区間 / すべて)を切り替えます。
struct MacOSSessionLogAnalysisRoadRegulationFilter: View {
    /// 選ばれている切替です。
    let selection: SessionRoadRegulationReviewFilter
    /// 選んだ切替を送出します。
    let onSelect: (SessionRoadRegulationReviewFilter) -> Void

    /// 切替を segmented で描画します。
    ///
    /// 責務: 状態の切替を選択として示し、選び直した値だけを送出します(保持は Application 側)。
    var body: some View {
        Picker("analysis.road_regulation.filter.title", selection: binding) {
            ForEach(SessionRoadRegulationReviewFilter.allCases) { filter in
                Text(LocalizedStringKey(filter.titleKey)).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("macos-analysis-road-regulation-filter")
    }

    /// 状態の値を読み、選び直しを送出に変える束縛です。
    private var binding: Binding<SessionRoadRegulationReviewFilter> {
        Binding(get: { selection }, set: { onSelect($0) })
    }
}
#endif
