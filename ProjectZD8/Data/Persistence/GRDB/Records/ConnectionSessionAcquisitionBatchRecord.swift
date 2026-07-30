import GRDB

/// GRDBへ保存する取得batchの永続化表現です。
struct ConnectionSessionAcquisitionBatchRecord: Codable, FetchableRecord, PersistableRecord {
    /// batch表名です。
    static let databaseTableName = "connection_session_acquisition_batches"
    /// 親session識別子です。
    let sessionID: String
    /// session内batch番号です。
    let batchOrdinal: Int64
    /// 取得世代です。
    let generation: Int64
    /// policy tickです。
    let policyTick: Int64
    /// policy評価完了の有無です。
    let selectionEvaluationComplete: Bool
    /// batch開始microsecondです。
    let startedAtMicroseconds: Int64
    /// terminal状態です。
    let completionState: String?
    /// terminal確定microsecondです。
    let completedAtMicroseconds: Int64?
    /// batch failure codeです。
    let failureCode: String?
    /// terminal sealの有無です。
    let isSealed: Bool
}
