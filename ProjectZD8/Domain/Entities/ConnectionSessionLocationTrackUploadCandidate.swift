/// アップロード候補のセッションと、その時点のローカル水位・同期記録です。
nonisolated struct ConnectionSessionLocationTrackUploadCandidate: Equatable, Sendable {
    /// 対象の接続セッション。
    let sessionID: ConnectionSessionID
    /// ローカルの軌跡の水位。
    let localWatermark: ConnectionSessionLocationTrackWatermark
    /// 既存の同期記録。無ければ nil。
    let syncRecord: ConnectionSessionLocationTrackSyncRecord?
}
