/// レコード単位の後勝ち(`modifiedAt` が新しい方を残す)で競合を解決します。
nonisolated struct SyncConflictResolver: Sendable {
    /// 解決結果です。
    nonisolated enum Resolution: Equatable, Sendable {
        /// リモートの内容をローカルへ適用する。
        case applyRemote
        /// ローカルの内容を残し、次の送信でサーバーを上書きする。
        case keepLocal
    }

    /// 責務: 解決器を生成します。
    init() {}

    /// 責務: ローカル行の状態とリモートの更新日時から、どちらを残すかを決めます。
    /// - Parameters:
    ///   - localModifiedAt: ローカル行の `modifiedAt`。行が無ければ `nil`。
    ///   - localIsPending: ローカル行に未送信の変更があるかどうか。
    ///   - remoteModifiedAt: リモートレコードの `modifiedAt`。
    func resolve(localModifiedAt: Int64?, localIsPending: Bool, remoteModifiedAt: Int64) -> Resolution {
        guard let localModifiedAt, localIsPending else { return .applyRemote }
        return remoteModifiedAt > localModifiedAt ? .applyRemote : .keepLocal
    }
}
