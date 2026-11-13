#if os(iOS)
import SwiftUI

/// 記録済みセッションを車両ごとに一覧する画面です。詳細は同じスタックへ push します。
struct IOSLogHistoryScreen: View {
    let state: LogHistoryState
    let send: (LogHistoryAction) -> Void

    @State private var isFilterPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if state.activeSessions.isEmpty, state.totalFinishedCount == 0 {
                    emptyState
                } else {
                    sessionList
                }
            }
            .background(InsightBackground())
            .navigationTitle(Text("tab.logs"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isFilterPresented = true } label: {
                        Label(
                            "logs.filter.title",
                            systemImage: state.hasActiveFilters
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                    .accessibilityValue(state.hasActiveFilters ? Text("logs.filter.active") : Text("logs.filter.inactive"))
                }
            }
            .navigationDestination(isPresented: detailBinding) {
                if let detail = state.detail {
                    IOSLogSessionDetailView(detail: detail, send: send)
                }
            }
            .refreshable { send(.refreshRequested) }
            .confirmationDialog(
                Text("logs.delete.title"),
                isPresented: deleteBinding,
                titleVisibility: .visible,
                presenting: state.pendingDeletion
            ) { _ in
                Button("logs.delete.confirm", role: .destructive) { send(.deleteConfirmed) }
                Button("common.cancel", role: .cancel) { send(.deleteCancelled) }
            } message: { prompt in
                Text("logs.delete.message \(prompt.sampleCount) \(prompt.payloadSizeText)")
            }
            .confirmationDialog(
                Text("logs.freeUp.title"),
                isPresented: freeUpBinding,
                titleVisibility: .visible,
                presenting: state.pendingFreeUp
            ) { _ in
                Button("logs.freeUp.confirm", role: .destructive) { send(.freeUpSpaceConfirmed) }
                Button("common.cancel", role: .cancel) { send(.freeUpSpaceCancelled) }
            } message: { prompt in
                Text("logs.freeUp.message \(prompt.payloadSizeText)")
            }
        }
        .sheet(isPresented: $isFilterPresented) {
            IOSLogFilterSheet(filter: state.filter, sortOrder: state.sortOrder, visibleCount: state.visibleCount, send: send)
        }
    }

    private var sessionList: some View {
        List {
            if let failure = state.failure {
                InlineBanner(
                    .error,
                    message: Text(LocalizedStringKey(failure.localizationKey)),
                    action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            if !state.activeSessions.isEmpty {
                Section {
                    ForEach(state.activeSessions) { row in
                        IOSLogSessionRow(row: row) { send(.detailRequested(row.id)) }
                    }
                } header: {
                    Text("logs.section.recording")
                }
            }
            if state.isFilteredEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: Text("logs.filteredEmpty.title"),
                    message: Text("logs.filteredEmpty.message"),
                    action: InsightAction(Text("logs.filter.reset")) { send(.filterReset) }
                )
                .listRowBackground(Color.clear)
            }
            ForEach(state.groups) { group in
                IOSLogVehicleSection(group: group, send: send)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack {
            if let failure = state.failure {
                InlineBanner(
                    .error,
                    message: Text(LocalizedStringKey(failure.localizationKey)),
                    action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                )
                .padding(InsightSpacing.screenGutter)
            }
            EmptyStateView(
                symbol: "list.bullet.rectangle",
                title: Text("logs.empty.title"),
                message: Text("logs.empty.message")
            )
        }
        .frame(maxHeight: .infinity)
    }

    private var detailBinding: Binding<Bool> {
        Binding(get: { state.detail != nil }, set: { if !$0 { send(.detailClosed) } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { state.pendingDeletion != nil }, set: { if !$0 { send(.deleteCancelled) } })
    }

    private var freeUpBinding: Binding<Bool> {
        Binding(get: { state.pendingFreeUp != nil }, set: { if !$0 { send(.freeUpSpaceCancelled) } })
    }
}
#endif
