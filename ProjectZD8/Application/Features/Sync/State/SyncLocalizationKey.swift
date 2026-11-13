/// 同期の状態と失敗を、両プラットフォームで共通の文言キー(String Catalog)へ対応付けます。
nonisolated enum SyncLocalizationKey {
    /// 責務: 同期状態を説明する文言キーを返します。
    static func status(_ status: CloudSyncStatus) -> String {
        switch status {
        case .unavailable(.noAccount): "sync.status.unavailable.noAccount"
        case .unavailable(.restricted): "sync.status.unavailable.restricted"
        case .unavailable(.temporarilyUnavailable): "sync.status.unavailable.temporarilyUnavailable"
        case .idle(lastSyncedAt: nil): "sync.status.idle.never"
        case .idle: "sync.status.idle.synced"
        case .syncing: "sync.status.syncing"
        case .failed: "sync.status.failed"
        }
    }

    /// 責務: 同期の失敗を説明する文言キーを返します。
    static func failure(_ failure: CloudSyncFailure) -> String {
        switch failure {
        case .network: "sync.failure.network"
        case .quotaExceeded: "sync.failure.quotaExceeded"
        case .integrity: "sync.failure.integrity"
        case .notFound: "sync.failure.notFound"
        case .other: "sync.failure.other"
        }
    }
}
