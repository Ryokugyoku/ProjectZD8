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
        guard let session = try fetchSession(sessionID, database: database), session.endedAt == nil,
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
        try insertNumbered([entry], into: session, in: database)
        return entry
    }

    /// 呼出元が採番済みのRaw entry群を追加し親集計を1回で更新します。
    ///
    /// 責務: 検証済みopen sessionへRaw行を順にinsertし、件数・バイト数・転送状態を同期します。
    /// - Parameters:
    ///   - entries: 採番済みsequenceを持つ追加対象。空なら何も書きません。
    ///   - session: 呼出元が同じtransactionで読み取った未終了session。
    ///   - database: 呼出元が所有するGRDB transaction境界。
    /// - Throws: 主キー重複などのSQLite制約違反、または保存失敗。
    func insertNumbered(
        _ entries: [ConnectionSessionRawLogEntry],
        into session: ConnectionSession,
        in database: Database
    ) throws {
        guard !entries.isEmpty else { return }
        var session = session
        for entry in entries {
            try ConnectionSessionRawLogRecord(entry: entry, sessionID: session.id).insert(database)
        }
        session.rawLogSummary.recordCount += Int64(entries.count)
        session.rawLogSummary.byteCount += entries.reduce(Int64(0)) { $0 + Int64($1.payload.count) }
        session.rawLogSummary.localState = .available
        session.rawLogSummary.cloudState = .pending
        session.rawLogSummary.manifestDigest = nil
        session.rawLogSummary.macImportReceipt = nil
        session.rawLogSummary.lastAccessedAt = nil
        try ConnectionSessionRecord(session: session).update(database)
    }

    /// SQLiteから親接続sessionを復元します。
    ///
    /// 責務: 1件のsession keyを検証済みDomain sessionへ変換します。
    /// - Parameters:
    ///   - sessionID: 復元する接続session識別子。
    ///   - database: 現在のGRDB境界。
    /// - Returns: 保存済みsession、または不在時の `nil`。
    /// - Throws: 保存値がDomainへ復元できない場合は整合性エラー。
    func fetchSession(
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
