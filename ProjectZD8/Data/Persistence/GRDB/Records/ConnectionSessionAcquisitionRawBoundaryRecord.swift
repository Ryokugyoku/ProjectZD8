import GRDB

/// 1件のappend-only Raw開始または終了境界を保持する永続化行です。
struct ConnectionSessionAcquisitionRawBoundaryRecord: Codable, FetchableRecord, PersistableRecord {
    /// Raw境界テーブル名です。
    static let databaseTableName = "connection_session_acquisition_raw_boundaries"

    /// 親接続セッションIDです。
    let sessionID: String
    /// `started` または `ended` のevent種別です。
    let eventKind: String
    /// Unix epochからのmicrosecond時刻です。
    let occurredAtMicroseconds: Int64
    /// 終了eventの直接原因です。
    let endReason: String?
}
