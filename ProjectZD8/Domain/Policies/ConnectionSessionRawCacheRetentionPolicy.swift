import Foundation

/// CloudKit保存済みRawログを端末へ保持する期間を判定します。
struct ConnectionSessionRawCacheRetentionPolicy {
    /// Rawログを最後の閲覧から保持する秒数です。
    let retentionInterval: TimeInterval

    /// 標準の3日保持期間を固定して生成します。
    ///
    /// 責務: Rawキャッシュ保持期間を3日間の既定値へ固定します。
    /// - Parameter retentionInterval: 最終閲覧から保持する秒数。
    init(retentionInterval: TimeInterval = 3 * 24 * 60 * 60) {
        self.retentionInterval = retentionInterval
    }

    /// 指定日時時点で端末Rawキャッシュを退避できるかを返します。
    ///
    /// 責務: 1件の終了済みセッションをCloudKit保護状態と最終閲覧経過時間で退避判定します。
    /// - Parameters:
    ///   - session: 退避候補の接続セッション。
    ///   - now: 判定基準日時。
    /// - Returns: ローカルRawだけを削除してよい場合は `true`。
    func shouldEvict(_ session: ConnectionSession, at now: Date) -> Bool {
        guard session.endedAt != nil,
              session.rawLogSummary.localState == .available,
              session.rawLogSummary.cloudState == .uploaded,
              session.rawLogSummary.manifestDigest?.isEmpty == false else { return false }
        let lastReference = session.rawLogSummary.lastAccessedAt ?? session.endedAt ?? session.startedAt
        return now.timeIntervalSince(lastReference) >= retentionInterval
    }
}
