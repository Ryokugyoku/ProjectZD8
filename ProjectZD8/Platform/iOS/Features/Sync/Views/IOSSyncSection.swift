#if os(iOS)
import SwiftUI

/// iCloud同期の状態・今すぐ同期・全データ削除のセクションです。
struct IOSSyncSection: View {
    let state: SyncState
    let send: (SyncAction) -> Void

    var body: some View {
        Section {
            LabeledContent("settings.sync.status") {
                HStack(spacing: InsightSpacing.sm) {
                    if state.status == .syncing { ProgressView() }
                    Text(LocalizedStringKey(state.statusMessageKey)).multilineTextAlignment(.trailing)
                }
            }
            if let key = state.statusFailureMessageKey {
                Label(LocalizedStringKey(key), systemImage: "exclamationmark.triangle.fill")
                    .font(InsightTypography.caption)
                    .foregroundStyle(InsightPalette.warning)
            }
            LabeledContent("settings.sync.lastSynced") {
                if let date = state.lastSyncedAt {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                } else {
                    Text("settings.sync.never").foregroundStyle(.secondary)
                }
            }
            Button {
                send(.syncNowTapped)
            } label: {
                HStack {
                    Text("settings.sync.syncNow")
                    if state.isSyncNowRunning { Spacer(); ProgressView() }
                }
            }
            .disabled(!state.canSyncNow)
            if let key = state.syncNowFailureMessageKey {
                InlineBanner(
                    .error,
                    message: Text(LocalizedStringKey(key)),
                    action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("settings.sync.header")
        } footer: {
            Text("settings.sync.footer")
        }
        Section {
            Button("settings.erase.button", role: .destructive) { send(.eraseAllRequested) }
                .disabled(!state.canEraseAll)
            if state.erasePhase == .erasing {
                HStack(spacing: InsightSpacing.sm) {
                    ProgressView()
                    Text("settings.erase.inProgress").foregroundStyle(.secondary)
                }
            }
            if state.erasePhase == .completed {
                InlineBanner(
                    .info,
                    message: Text("settings.erase.completed"),
                    action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let key = state.eraseFailureMessageKey {
                InlineBanner(
                    .error,
                    title: Text("settings.erase.failed"),
                    message: Text(LocalizedStringKey(key)),
                    action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("settings.erase.header")
        } footer: {
            Text("settings.erase.footer")
        }
        .confirmationDialog(
            Text("settings.erase.confirmTitle"),
            isPresented: Binding(get: { state.erasePhase == .confirming }, set: { if !$0 { send(.eraseAllCancelled) } }),
            titleVisibility: .visible
        ) {
            Button("settings.erase.confirm", role: .destructive) { send(.eraseAllConfirmed) }
            Button("common.cancel", role: .cancel) { send(.eraseAllCancelled) }
        } message: {
            Text("settings.erase.confirmMessage")
        }
    }
}
#endif
