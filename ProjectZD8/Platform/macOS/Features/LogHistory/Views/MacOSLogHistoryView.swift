#if os(macOS)
import SwiftUI

/// ログ画面。左に車両別のセッション一覧と絞り込み、右に選択したセッションの詳細を出す。
struct MacOSLogHistoryView: View {
    let state: LogHistoryState
    let send: (LogHistoryAction) -> Void

    var body: some View {
        HSplitView {
            listPane
                .frame(minWidth: 420, idealWidth: 560)
            detailPane
                .frame(minWidth: 340, idealWidth: 420)
        }
        .background(InsightBackground())
        .navigationTitle(Text("shell.destination.logs"))
        .confirmationDialog(
            Text("history.delete.title"),
            isPresented: Binding(
                get: { state.pendingDeletion != nil },
                set: { if !$0, state.pendingDeletion != nil { send(.deleteCancelled) } }
            ),
            titleVisibility: .visible,
            presenting: state.pendingDeletion
        ) { _ in
            Button(role: .destructive) {
                send(.deleteConfirmed)
            } label: {
                Text("history.delete.confirm")
            }
            Button(role: .cancel) {
                send(.deleteCancelled)
            } label: {
                Text("common.cancel")
            }
        } message: { prompt in
            Text("history.delete.message \(prompt.sampleCount) \(prompt.payloadSizeText)")
        }
        .confirmationDialog(
            Text("history.free_up.title"),
            isPresented: Binding(
                get: { state.pendingFreeUp != nil },
                set: { if !$0, state.pendingFreeUp != nil { send(.freeUpSpaceCancelled) } }
            ),
            titleVisibility: .visible,
            presenting: state.pendingFreeUp
        ) { _ in
            Button {
                send(.freeUpSpaceConfirmed)
            } label: {
                Text("history.free_up.confirm")
            }
            Button(role: .cancel) {
                send(.freeUpSpaceCancelled)
            } label: {
                Text("common.cancel")
            }
        } message: { _ in
            Text("history.free_up.message")
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: InsightSpacing.md) {
            MacOSLogFilterBar(state: state, send: send)
                .padding(.horizontal, InsightSpacing.lg)
                .padding(.top, InsightSpacing.md)
            if let failure = state.failure {
                InlineBanner(
                    .error,
                    message: Text(LocalizedStringKey(failure.localizationKey)),
                    action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                )
                .padding(.horizontal, InsightSpacing.lg)
            }
            listContent
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if state.loadPhase != .loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if state.activeSessions.isEmpty && state.totalFinishedCount == 0 {
            EmptyStateView(
                symbol: "list.bullet.rectangle",
                title: Text("history.empty.title"),
                message: Text("history.empty.message")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: InsightSpacing.xl) {
                    if !state.activeSessions.isEmpty {
                        VStack(alignment: .leading, spacing: InsightSpacing.sm) {
                            InsightSectionHeader(Text("history.section.active"))
                            ForEach(state.activeSessions) { row in
                                MacOSLogSessionRow(row: row, isSelected: row.id == state.detail?.row.id) {
                                    send(.detailRequested(row.id))
                                }
                            }
                        }
                    }
                    if state.isFilteredEmpty {
                        EmptyStateView(
                            symbol: "line.3.horizontal.decrease.circle",
                            title: Text("history.filtered_empty.title"),
                            message: Text("history.filtered_empty.message"),
                            action: InsightAction(Text("history.filter.reset")) { send(.filterReset) }
                        )
                    }
                    ForEach(state.groups) { group in
                        MacOSLogGroupSection(group: group, selectedID: state.detail?.row.id) { send(.detailRequested($0)) }
                    }
                }
                .padding(InsightSpacing.lg)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let detail = state.detail {
            MacOSLogDetailView(detail: detail, send: send)
        } else {
            EmptyStateView(symbol: "sidebar.right", title: Text("history.detail.placeholder"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
