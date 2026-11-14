#if os(macOS)
import SwiftUI

/// 日付範囲、終了理由、並び順を同時指定できる絞り込みパネルです。
struct MacOSConnectionHistoryVehicleSessionsFilterPanel: View {
    /// 絞り込み条件と既定日付の算出元になる履歴状態です。
    let state: ConnectionHistoryState
    /// 絞り込み操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void
    /// 画面サイズに対応する表示倍率です。
    let scale: CGFloat

    /// 見出し、解除操作、個別操作を描画します。
    ///
    /// 責務: 現在の絞り込み状態を見出しと幅に応じた操作列へ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 13 * scale) {
            HStack {
                Label("history.filter.title", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
                Spacer()
                if state.hasActiveFilters { Button("history.filter.reset") { send(.filtersReset) }.buttonStyle(.borderless) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14 * scale) { controls }
                VStack(alignment: .leading, spacing: 10 * scale) { controls }
            }
        }
        .padding(17 * scale)
        .background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
    }

    /// パネルに並べる日付、終了理由、並び順の個別操作です。
    @ViewBuilder private var controls: some View {
        MacOSConnectionHistoryVehicleSessionsDateFilter(
            titleKey: "history.filter.from",
            date: state.filterStartDate,
            fallback: state.closedSessions.map(\.startedAt).min() ?? .distantPast,
            scale: scale
        ) { send(.filterStartDateChanged($0)) }
        MacOSConnectionHistoryVehicleSessionsDateFilter(
            titleKey: "history.filter.to",
            date: state.filterEndDate,
            fallback: state.closedSessions.map(\.startedAt).max() ?? .distantPast,
            scale: scale
        ) { send(.filterEndDateChanged($0)) }
        Picker("history.filter.reason", selection: Binding(get: { state.endReasonFilter }, set: { send(.endReasonFilterChanged($0)) })) {
            ForEach(ConnectionHistoryEndReasonFilter.allCases, id: \.self) { Text(LocalizedStringKey($0.historyLocalizationKey)).tag($0) }
        }.frame(minWidth: 150 * scale)
        Picker("history.sort.title", selection: Binding(get: { state.sortOrder }, set: { send(.sortOrderChanged($0)) })) {
            ForEach(ConnectionHistorySortOrder.allCases, id: \.self) { Text(LocalizedStringKey($0.historyLocalizationKey)).tag($0) }
        }.frame(minWidth: 150 * scale)
    }
}
#endif
