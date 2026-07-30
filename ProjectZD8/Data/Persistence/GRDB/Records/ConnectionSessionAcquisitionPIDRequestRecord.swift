import GRDB

/// GRDBへ保存するPID request evidenceの永続化表現です。
struct ConnectionSessionAcquisitionPIDRequestRecord: Codable, FetchableRecord, PersistableRecord {
    /// request evidence表名です。
    static let databaseTableName = "connection_session_acquisition_pid_requests"
    /// 親session識別子です。
    let sessionID: String
    /// 親batch番号です。
    let batchOrdinal: Int64
    /// batch内要求順です。
    let requestOrdinal: Int
    /// manifest ordered PID位置です。
    let manifestPIDOrdinal: Int
    /// dispatch進行状態です。
    let dispatchState: String
    /// terminal transport outcomeです。
    let transportOutcome: String?
    /// value outcomeです。
    let valueOutcome: String
    /// responded時のRaw sequenceです。
    let rawSequence: Int64?
    /// terminalまでの単調経過時間です。
    let elapsedNanoseconds: Int64?
    /// 承認済み分類理由codeです。
    let reasonCode: String?
    /// terminal sealの有無です。
    let isSealed: Bool
}
