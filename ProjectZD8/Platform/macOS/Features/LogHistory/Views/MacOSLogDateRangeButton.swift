#if os(macOS)
import SwiftUI

/// 開始日・終了日の絞り込みをポップオーバーで編集するボタン。
struct MacOSLogDateRangeButton: View {
    let filter: LogHistoryFilter
    let onChange: (LogHistoryFilter) -> Void

    @State private var isPresented = false

    private var isActive: Bool { filter.startDate != nil || filter.endDate != nil }

    var body: some View {
        FilterChip(Text("history.filter.dateRange"), isSelected: isActive) { isPresented = true }
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: InsightSpacing.md) {
                    dateRow(
                        titleKey: "history.filter.from",
                        date: filter.startDate,
                        set: { var next = filter; next.startDate = $0; onChange(next) }
                    )
                    dateRow(
                        titleKey: "history.filter.to",
                        date: filter.endDate,
                        set: { var next = filter; next.endDate = $0; onChange(next) }
                    )
                }
                .padding(InsightSpacing.lg)
                .frame(width: 280)
            }
    }

    private func dateRow(titleKey: LocalizedStringKey, date: Date?, set: @escaping (Date?) -> Void) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { date != nil },
                set: { set($0 ? Date() : nil) }
            )) {
                Text(titleKey)
            }
            Spacer()
            if let date {
                DatePicker(
                    selection: Binding(get: { date }, set: { set($0) }),
                    displayedComponents: .date
                ) {
                    Text(titleKey)
                }
                .labelsHidden()
            }
        }
    }
}
#endif
