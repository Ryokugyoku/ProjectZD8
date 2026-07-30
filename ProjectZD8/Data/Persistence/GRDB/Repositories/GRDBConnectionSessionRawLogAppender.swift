import Foundation
import GRDB

/// 既存Raw表への採番追記と親session集計更新を同じGRDB境界で実行します。
struct GRDBConnectionSessionRawLogAppender {
    /// 未デコード応答を次のRaw sequenceへ追加します。
    ///
    /// 責務: 1件の未デコード応答をopen sessionへ採番追記して親集計を同期します。
    /// - Parameters:
    ///   - observation: 追加する未デコード応答。
    ///   - sessionID: Rawと集計を所有する接続session。
    ///   - database: 呼出元が所有するGRDB transaction境界。
    /// - Returns: 採番済みsequenceを持つcanonical Raw entry。
    /// - Throws: session不在、終了済み、整数範囲外、またはSQLite保存失敗。
    func append(
        _ observation: OBDRawResponseObservation,
        to sessionID: ConnectionSessionID,
        in database: Database
    ) throws -> ConnectionSessionRawLogEntry {
        guard var session = try fetchSession(sessionID, database: database), session.endedAt == nil,
              let elapsed = Int64(exactly: observation.batchElapsedNanoseconds) else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        let sessionKey = sessionID.rawValue.uuidString.lowercased()
        guard let sequence = try Int64.fetchOne(
            database,
            sql: "SELECT COALESCE(MAX(sequence), -1) + 1 FROM connection_session_raw_logs WHERE sessionID = ?",
            arguments: [sessionKey]
        ) else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        let entry = ConnectionSessionRawLogEntry(
            sequence: sequence,
            observedAt: observation.observedAt,
            batchElapsedNanoseconds: UInt64(elapsed),
            service: observation.request.service,
            pid: observation.request.pid,
            payload: observation.payload
        )
        try ConnectionSessionRawLogRecord(entry: entry, sessionID: sessionID).insert(database)
        session.rawLogSummary.recordCount += 1
        session.rawLogSummary.byteCount += Int64(observation.payload.count)
        session.rawLogSummary.localState = .available
        session.rawLogSummary.cloudState = .pending
        session.rawLogSummary.manifestDigest = nil
        session.rawLogSummary.macImportReceipt = nil
        session.rawLogSummary.lastAccessedAt = nil
        try ConnectionSessionRecord(session: session).update(database)
        return entry
    }

    /// SQLiteから親接続sessionを復元します。
    ///
    /// 責務: 1件のsession keyを検証済みDomain sessionへ変換します。
    /// - Parameters:
    ///   - sessionID: 復元する接続session識別子。
    ///   - database: 現在のGRDB境界。
    /// - Returns: 保存済みsession、または不在時の `nil`。
    /// - Throws: 保存値がDomainへ復元できない場合は整合性エラー。
    private func fetchSession(
        _ sessionID: ConnectionSessionID,
        database: Database
    ) throws -> ConnectionSession? {
        let key = sessionID.rawValue.uuidString.lowercased()
        guard let record = try ConnectionSessionRecord.fetchOne(database, key: key) else { return nil }
        guard let session = record.makeDomainSession() else {
            throw ConnectionSessionRepositoryError.integrityConflict
        }
        return session
    }
}
