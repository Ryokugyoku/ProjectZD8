#if os(macOS)
import SwiftUI

/// 「iCloud」タブ: 同期状態・最終同期・今すぐ同期・全データ削除。
struct MacOSICloudSettingsView: View {
    let state: SyncState
    let send: (SyncAction) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: InsightSpacing.sm) {
                        if state.status == .syncing || state.isSyncNowRunning { ProgressView().controlSize(.small) }
                        Text(LocalizedStringKey(state.statusMessageKey))
                    }
                } label: {
                    Text("sync.status.label")
                }
                LabeledContent {
                    if let last = state.lastSyncedAt {
                        Text(last, format: .dateTime.year().month().day().hour().minute())
                    } else {
                        Text("sync.status.lastSyncedNever").foregroundStyle(.secondary)
                    }
                } label: {
                    Text("sync.status.lastSyncedLabel")
                }
                if let key = state.statusFailureMessageKey {
                    InlineBanner(.error, message: Text(LocalizedStringKey(key)))
                }
                if let key = state.syncNowFailureMessageKey {
                    InlineBanner(
                        .error,
                        message: Text(LocalizedStringKey(key)),
                        action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                    )
                }
                Button {
                    send(.syncNowTapped)
                } label: {
                    Text("sync.action.syncNow")
                }
                .disabled(!state.canSyncNow)
            }

            Section {
                Text("sync.erase.description").font(InsightTypography.caption).foregroundStyle(.secondary)
                switch state.erasePhase {
                case .erasing:
                    HStack(spacing: InsightSpacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("sync.erase.inProgress")
                    }
                case .failed:
                    if let key = state.eraseFailureMessageKey {
                        InlineBanner(
                            .error,
                            title: Text("sync.erase.failed.title"),
                            message: Text(LocalizedStringKey(key)),
                            action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                        )
                    }
                case .completed:
                    InlineBanner(
                        .info,
                        message: Text("sync.erase.completed"),
                        action: InsightAction(Text("common.dismiss")) { send(.failureDismissed) }
                    )
                case .idle, .confirming:
                    EmptyView()
                }
                Button(role: .destructive) {
                    send(.eraseAllRequested)
                } label: {
                    Text("sync.action.eraseAll")
                }
                .disabled(!state.canEraseAll)
            } header: {
                Text("sync.erase.header")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            Text("sync.erase.confirm.title"),
            isPresented: Binding(
                get: { state.erasePhase == .confirming },
                set: { if !$0, state.erasePhase == .confirming { send(.eraseAllCancelled) } }
            ),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                send(.eraseAllConfirmed)
            } label: {
                Text("sync.erase.confirm.action")
            }
            Button(role: .cancel) {
                send(.eraseAllCancelled)
            } label: {
                Text("common.cancel")
            }
        } message: {
            Text("sync.erase.confirm.message")
        }
    }
}
#endif
