import Foundation

/// 同期画面が描画する状態です。
nonisolated struct SyncState: Equatable, Sendable {
    /// 現在の同期状態です。購読を始めるまでは「一時的に利用不可」です。
    var status: CloudSyncStatus = .unavailable(.temporarilyUnavailable)
    /// 最後に同期を終えた日時です。状態が待機中以外に変わっても保持します。
    var lastSyncedAt: Date?
    /// 「今すぐ同期」を実行中かどうかです。
    var isSyncNowRunning = false
    /// 直近の「今すぐ同期」の失敗です。
    var syncNowFailure: CloudSyncFailure?
    /// 全データ削除の段階です。
    var erasePhase: SyncEraseAllPhase = .idle

    /// 責務: 既定の初期状態を生成します。
    init() {}

    /// 同期状態を説明する文言キーです。
    var statusMessageKey: String { SyncLocalizationKey.status(status) }

    /// 状態が失敗の時、その理由を説明する文言キーです。
    var statusFailureMessageKey: String? {
        guard case .failed(let failure) = status else { return nil }
        return SyncLocalizationKey.failure(failure)
    }

    /// 「今すぐ同期」の失敗を説明する文言キーです。
    var syncNowFailureMessageKey: String? { syncNowFailure.map(SyncLocalizationKey.failure) }

    /// 全データ削除の失敗を説明する文言キーです。
    var eraseFailureMessageKey: String? {
        guard case .failed(let failure) = erasePhase else { return nil }
        return SyncLocalizationKey.failure(failure)
    }

    /// 「今すぐ同期」を押せるかどうかです。
    var canSyncNow: Bool {
        switch status {
        case .unavailable, .syncing: false
        case .idle, .failed: !isSyncNowRunning && erasePhase != .erasing
        }
    }

    /// 全データ削除を要求できるかどうかです。
    var canEraseAll: Bool { erasePhase != .erasing && !isSyncNowRunning }
}
