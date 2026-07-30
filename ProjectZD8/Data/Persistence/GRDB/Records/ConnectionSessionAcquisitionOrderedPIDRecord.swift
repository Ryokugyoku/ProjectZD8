import GRDB

/// 1件のPID要求順位置を保持する永続化行です。
struct ConnectionSessionAcquisitionOrderedPIDRecord: Codable, FetchableRecord, PersistableRecord {
    /// PID要求順テーブル名です。
    static let databaseTableName = "connection_session_acquisition_ordered_pids"

    /// 親接続セッションIDです。
    let sessionID: String
    /// 0から始まる要求順位置です。
    let ordinal: Int
    /// OBD Service番号です。
    let service: Int
    /// Service内PID番号です。
    let pid: Int
}
