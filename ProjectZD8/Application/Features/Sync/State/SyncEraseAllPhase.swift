/// 全データ削除の操作の段階です。
nonisolated enum SyncEraseAllPhase: Equatable, Sendable {
    /// 操作していない。
    case idle
    /// 確認を表示している。
    case confirming
    /// iCloudとこの端末から削除している。
    case erasing
    /// 直近の削除が完了した。
    case completed
    /// 削除に失敗した。
    case failed(CloudSyncFailure)
}
