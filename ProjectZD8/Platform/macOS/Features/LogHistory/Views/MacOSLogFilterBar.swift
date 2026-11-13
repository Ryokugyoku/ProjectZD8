#if os(macOS)
import SwiftUI

/// ログ一覧の絞り込み・並べ替えバー(期間・終了理由・実走行/デモ・並び順)。
struct MacOSLogFilterBar: View {
    let state: LogHistoryState
    let send: (LogHistoryAction) -> Void

    var body: some View {
        HStack(spacing: InsightSpacing.sm) {
            MacOSLogDateRangeButton(filter: state.filter) { send(.filterChanged($0)) }

            Menu {
                Button {
                    update { $0.endReason = nil }
                } label: {
                    Text("history.filter.reason.any")
                }
                Divider()
                ForEach(SessionEndReason.allCases, id: \.self) { reason in
                    Button {
                        update { $0.endReason = reason }
                    } label: {
                        Text(LocalizedStringKey("history.reason.\(reason.rawValue)"))
                    }
                }
            } label: {
                chipLabel("history.filter.reason", isActive: state.filter.endReason != nil)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()

            Picker(selection: Binding(
                get: { state.filter.dataKind },
                set: { value in update { $0.dataKind = value } }
            )) {
                ForEach(LogHistoryDataKindFilter.allCases, id: \.self) { kind in
                    Text(LocalizedStringKey(kind.nameKey)).tag(kind)
                }
            } label: {
                Text("history.filter.data_kind")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if state.hasActiveFilters {
                Button {
                    send(.filterReset)
                } label: {
                    Text("history.filter.reset")
                }
                .buttonStyle(.link)
            }

            Spacer(minLength: InsightSpacing.md)

            Picker(selection: Binding(
                get: { state.sortOrder },
                set: { send(.sortOrderChanged($0)) }
            )) {
                ForEach(LogHistorySortOrder.allCases, id: \.self) { order in
                    Text(LocalizedStringKey(order.nameKey)).tag(order)
                }
            } label: {
                Text("history.sort.title")
            }
            .fixedSize()
        }
    }

    private func update(_ change: (inout LogHistoryFilter) -> Void) {
        var next = state.filter
        change(&next)
        send(.filterChanged(next))
    }

    private func chipLabel(_ key: LocalizedStringKey, isActive: Bool) -> some View {
        HStack(spacing: InsightSpacing.xs) {
            Text(key)
            Image(systemName: "chevron.down").imageScale(.small)
        }
        .font(InsightTypography.label)
        .padding(.horizontal, InsightSpacing.md)
        .padding(.vertical, InsightSpacing.xs + 2)
        .background(Capsule().fill(isActive ? InsightPalette.accent.opacity(0.18) : InsightPalette.surface))
        .overlay(Capsule().strokeBorder(isActive ? InsightPalette.accent : InsightPalette.stroke, lineWidth: 1))
        .foregroundStyle(isActive ? InsightPalette.accent : Color.primary)
    }
}
#endif
