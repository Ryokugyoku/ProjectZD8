import Foundation
import Observation

/// iCloud同期の状態表示・今すぐ同期・全データ削除を管理します。
@MainActor
@Observable
final class SyncModel {
    /// 画面が描画する状態です。
    private(set) var state = SyncState()

    @ObservationIgnored private let sync: any CloudSyncPort
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    /// 責務: 同期ポートを受け取ります。購読は `appeared` で始めます。
    init(sync: any CloudSyncPort) {
        self.sync = sync
    }

    isolated deinit {
        statusTask?.cancel()
    }

    /// 責務: 操作を状態遷移へ変換します。
    func send(_ action: SyncAction) {
        switch action {
        case .appeared:
            observeStatus()
        case .syncNowTapped:
            syncNow()
        case .eraseAllRequested:
            guard state.canEraseAll else { return }
            state.erasePhase = .confirming
        case .eraseAllConfirmed:
            eraseAll()
        case .eraseAllCancelled:
            guard state.erasePhase == .confirming else { return }
            state.erasePhase = .idle
        case .failureDismissed:
            state.syncNowFailure = nil
            switch state.erasePhase {
            case .failed, .completed: state.erasePhase = .idle
            case .idle, .confirming, .erasing: break
            }
        }
    }

    /// 責務: 同期状態の購読を1回だけ始めます。
    private func observeStatus() {
        guard statusTask == nil else { return }
        let updates = sync.statusUpdates()
        statusTask = Task { [weak self] in
            for await status in updates {
                self?.apply(status)
            }
        }
    }

    /// 責務: 受け取った同期状態を反映します。
    private func apply(_ status: CloudSyncStatus) {
        state.status = status
        if case .idle(let lastSyncedAt?) = status {
            state.lastSyncedAt = lastSyncedAt
        }
    }

    /// 責務: 今すぐ同期を1件だけ実行し、失敗を型付きで残します。
    private func syncNow() {
        guard state.canSyncNow else { return }
        state.isSyncNowRunning = true
        state.syncNowFailure = nil
        Task {
            do {
                try await sync.syncNow()
            } catch {
                state.syncNowFailure = Self.failure(from: error)
            }
            state.isSyncNowRunning = false
        }
    }

    /// 責務: 確認済みの全データ削除を実行します。
    private func eraseAll() {
        guard state.erasePhase == .confirming else { return }
        state.erasePhase = .erasing
        Task {
            do {
                try await sync.eraseAllData()
                state.erasePhase = .completed
                state.lastSyncedAt = nil
            } catch {
                state.erasePhase = .failed(Self.failure(from: error))
            }
        }
    }

    /// 責務: ポートが投げたエラーを同期の失敗へ変換します。契約外のエラーは `.other` です。
    private static func failure(from error: any Error) -> CloudSyncFailure {
        error as? CloudSyncFailure ?? .other
    }
}
