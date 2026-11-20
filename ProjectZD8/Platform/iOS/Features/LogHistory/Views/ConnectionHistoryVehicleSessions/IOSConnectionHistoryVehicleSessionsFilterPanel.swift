#if os(iOS)
import SwiftUI

/// 日付範囲、終了理由、並び順を同時指定できる絞り込みパネルです。
struct IOSConnectionHistoryVehicleSessionsFilterPanel: View {
    /// 絞り込み条件と既定日付の算出元になる履歴状態です。
    let state: ConnectionHistoryState
    /// 絞り込み操作をApplicationへ通知します。
    let send: (ConnectionHistoryAction) -> Void

    /// 日付条件を有効にした時の初期日を決めます。
    private let dateFallback = ConnectionHistoryFilterDateFallback()

    /// 見出し、解除操作、日付・終了理由・並び順の操作を描画します。
    ///
    /// 責務: 現在の絞り込み状態を見出しと個別操作の列へ配置します。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("history.filter.title", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                if state.hasActiveFilters { Button("history.filter.reset") { send(.filtersReset) }.font(.caption.weight(.bold)) }
            }
            IOSConnectionHistoryVehicleSessionsDateFilter(
                titleKey: "history.filter.from",
                date: state.filterStartDate,
                fallback: dateFallback.startDate(in: state.closedSessions)
            ) { send(.filterStartDateChanged($0)) }
            IOSConnectionHistoryVehicleSessionsDateFilter(
                titleKey: "history.filter.to",
                date: state.filterEndDate,
                fallback: dateFallback.endDate(in: state.closedSessions)
            ) { send(.filterEndDateChanged($0)) }
            Picker("history.filter.reason", selection: Binding(get: { state.endReasonFilter }, set: { send(.endReasonFilterChanged($0)) })) {
                ForEach(ConnectionHistoryEndReasonFilter.allCases, id: \.self) { Text(LocalizedStringKey($0.historyLocalizationKey)).tag($0) }
            }
            Picker("history.sort.title", selection: Binding(get: { state.sortOrder }, set: { send(.sortOrderChanged($0)) })) {
                ForEach(ConnectionHistorySortOrder.allCases, id: \.self) { Text(LocalizedStringKey($0.historyLocalizationKey)).tag($0) }
            }
        }
        .pickerStyle(.menu)
        .padding(17)
        .background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
