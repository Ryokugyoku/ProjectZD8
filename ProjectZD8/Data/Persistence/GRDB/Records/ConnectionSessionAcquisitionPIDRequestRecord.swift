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

extension ConnectionSessionAcquisitionPIDRequestRecord {
    /// Domain request証拠をGRDB保存値へ変換します。
    ///
    /// 責務: 1件の要求証拠を親session/batch付きの永続化表現へ変換し、terminalならseal済みにします。
    /// - Parameters:
    ///   - request: 変換する要求証拠。
    ///   - sessionID: 親sessionのDB key。
    ///   - batchOrdinal: 親batch番号。
    /// - Throws: 経過時間がInt64範囲外の場合は `ConnectionSessionRepositoryError.integrityConflict`。
    init(request: PIDRequestEvidence, sessionID: String, batchOrdinal: Int64) throws {
        let elapsed = try request.elapsedNanoseconds.map { value -> Int64 in
            guard let converted = Int64(exactly: value) else {
                throw ConnectionSessionRepositoryError.integrityConflict
            }
            return converted
        }
        self.init(
            sessionID: sessionID,
            batchOrdinal: batchOrdinal,
            requestOrdinal: request.requestOrdinal,
            manifestPIDOrdinal: request.manifestPIDOrdinal,
            dispatchState: request.dispatchState.rawValue,
            transportOutcome: request.transportOutcome?.rawValue,
            valueOutcome: request.valueOutcome.rawValue,
            rawSequence: request.rawSequence,
            elapsedNanoseconds: elapsed,
            reasonCode: request.reasonCode,
            isSealed: request.dispatchState == .terminal
        )
    }
}
