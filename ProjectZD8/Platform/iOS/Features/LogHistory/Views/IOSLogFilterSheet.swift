#if os(iOS)
import SwiftUI

/// 開始日・終了理由・実車/デモ・並び順を選ぶシートです。変更は即座にモデルへ反映します。
struct IOSLogFilterSheet: View {
    let filter: LogHistoryFilter
    let sortOrder: LogHistorySortOrder
    let visibleCount: Int
    let send: (LogHistoryAction) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("logs.filter.dateRange") {
                    optionalDate("logs.filter.from", date: filter.startDate) { date in
                        var next = filter
                        next.startDate = date
                        send(.filterChanged(next))
                    }
                    optionalDate("logs.filter.to", date: filter.endDate) { date in
                        var next = filter
                        next.endDate = date
                        send(.filterChanged(next))
                    }
                }
                Section("logs.filter.endReason") {
                    Picker("logs.filter.endReason", selection: endReasonBinding) {
                        Text("logs.filter.anyReason").tag(SessionEndReason?.none)
                        ForEach(SessionEndReason.allCases, id: \.self) { reason in
                            Text(LocalizedStringKey("history.reason.\(reason.rawValue)")).tag(SessionEndReason?.some(reason))
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("logs.filter.dataKind") {
                    Picker("logs.filter.dataKind", selection: dataKindBinding) {
                        ForEach(LogHistoryDataKindFilter.allCases, id: \.self) { kind in
                            Text(LocalizedStringKey(kind.nameKey)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("logs.sort.title") {
                    Picker("logs.sort.title", selection: sortBinding) {
                        ForEach(LogHistorySortOrder.allCases, id: \.self) { order in
                            Text(LocalizedStringKey(order.nameKey)).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Button("logs.filter.reset", role: .destructive) { send(.filterReset) }
                        .disabled(!filter.isActive)
                } footer: {
                    Text("logs.filter.resultCount \(visibleCount)")
                }
            }
            .navigationTitle(Text("logs.filter.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 日付の有無を切り替えるトグルと、有効時だけ現れる日付選択です。
    private func optionalDate(_ title: LocalizedStringKey, date: Date?, set: @escaping (Date?) -> Void) -> some View {
        Group {
            Toggle(title, isOn: Binding(get: { date != nil }, set: { set($0 ? Date() : nil) }))
            if let date {
                DatePicker(
                    title,
                    selection: Binding(get: { date }, set: { set($0) }),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        }
    }

    private var endReasonBinding: Binding<SessionEndReason?> {
        Binding(get: { filter.endReason }, set: { reason in
            var next = filter
            next.endReason = reason
            send(.filterChanged(next))
        })
    }

    private var dataKindBinding: Binding<LogHistoryDataKindFilter> {
        Binding(get: { filter.dataKind }, set: { kind in
            var next = filter
            next.dataKind = kind
            send(.filterChanged(next))
        })
    }

    private var sortBinding: Binding<LogHistorySortOrder> {
        Binding(get: { sortOrder }, set: { send(.sortOrderChanged($0)) })
    }
}
#endif
