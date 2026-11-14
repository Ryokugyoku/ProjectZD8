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

extension ConnectionSessionAcquisitionBatchRecord {
    /// Domain batch証拠をGRDB保存値へ変換します。
    ///
    /// 責務: 1件のbatch証拠を、終端状態の有無に応じたseal列を含む永続化表現へ変換します。
    /// - Parameters:
    ///   - evidence: 保存するbatch証拠。`completionState` が `nil` なら未seal行になります。
    ///   - sessionID: 親sessionのDB key。
    /// - Throws: 取得世代・tickがInt64範囲外、または時刻を整数microsecondへ表現できない場合は
    ///   `ConnectionSessionRepositoryError.integrityConflict`。
    init(evidence: AcquisitionBatchEvidence, sessionID: String) throws {
        guard let generation = Int64(exactly: evidence.generation),
              let policyTick = Int64(exactly: evidence.policyTick) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        self.init(
            sessionID: sessionID,
            batchOrdinal: evidence.identity.ordinal,
            generation: generation,
            policyTick: policyTick,
            selectionEvaluationComplete: evidence.isSelectionEvaluationComplete,
            startedAtMicroseconds: try ConnectionSessionMicrosecondTimestamp.microseconds(for: evidence.startedAt),
            completionState: evidence.completionState?.rawValue,
            completedAtMicroseconds: try evidence.completedAt.map(ConnectionSessionMicrosecondTimestamp.microseconds),
            failureCode: evidence.failure?.rawValue,
            isSealed: evidence.completionState != nil
        )
    }
}
