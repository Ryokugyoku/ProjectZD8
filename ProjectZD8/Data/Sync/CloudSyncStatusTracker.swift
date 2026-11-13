import Foundation

/// アカウント状態・進行中の送受信・直近の結果から同期状態を導きます。
nonisolated struct CloudSyncStatusTracker: Equatable, Sendable {
    /// 同期を利用できない理由です。利用できれば `nil` です。
    private(set) var unavailableReason: CloudSyncUnavailableReason?
    /// 進行中の送受信の数です。
    private(set) var activeOperationCount = 0
    /// 最後に失敗なく同期を終えた日時です。
    private(set) var lastSyncedAt: Date?
    /// 直近の失敗です。次の成功で消えます。
    private(set) var lastFailure: CloudSyncFailure?

    /// 責務: 初期状態(利用可否が未確定)の追跡器を生成します。
    init(unavailableReason: CloudSyncUnavailableReason? = .temporarilyUnavailable, lastSyncedAt: Date? = nil) {
        self.unavailableReason = unavailableReason
        self.lastSyncedAt = lastSyncedAt
    }

    /// 現在の同期状態です。
    var status: CloudSyncStatus {
        if let unavailableReason { return .unavailable(unavailableReason) }
        if activeOperationCount > 0 { return .syncing }
        if let lastFailure { return .failed(lastFailure) }
        return .idle(lastSyncedAt: lastSyncedAt)
    }

    /// 責務: アカウントの利用可否を反映します。
    mutating func accountChanged(unavailableReason: CloudSyncUnavailableReason?) {
        self.unavailableReason = unavailableReason
        if unavailableReason != nil { activeOperationCount = 0 }
    }

    /// 責務: 送受信の開始を記録します。
    mutating func operationStarted() {
        activeOperationCount += 1
    }

    /// 責務: 送受信の終了を記録します。失敗が無ければ同期日時を更新し、直近の失敗を消します。
    mutating func operationFinished(at date: Date, failure: CloudSyncFailure?) {
        activeOperationCount = max(0, activeOperationCount - 1)
        if let failure {
            lastFailure = failure
        } else {
            lastFailure = nil
            lastSyncedAt = date
        }
    }

    /// 責務: 送受信とは別に起きた失敗(保存の個別失敗など)を記録します。
    mutating func recordFailure(_ failure: CloudSyncFailure) {
        lastFailure = failure
    }
}
