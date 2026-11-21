/// 軌跡アップロードの実行結果です。
nonisolated struct ConnectionSessionLocationTrackUploadReport: Equatable, Sendable {
    /// 今回アップロードしたセッション。
    let uploadedSessionIDs: [ConnectionSessionID]
    /// 削除済みのため iCloud から掃除したセッション。
    let purgedSessionIDs: Set<ConnectionSessionID>
}
