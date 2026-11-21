import Foundation
import GRDB

/// アップロード候補のセッションとローカル水位を問い合わせます。
nonisolated struct GRDBConnectionSessionLocationTrackCandidateQuery {
    /// 候補の問合せです。終了済み・アカウント一致・点か事象あり・同期記録なしか uploaded のセッションを返します。
    private static let sql = """
        SELECT s.id AS id,
               (SELECT COUNT(*) FROM connection_session_location_samples WHERE sessionID = s.id) AS sampleCount,
               (SELECT MAX(sequence) FROM connection_session_location_samples WHERE sessionID = s.id) AS lastSequence,
               (SELECT COUNT(*) FROM connection_session_location_events WHERE sessionID = s.id) AS eventCount,
               (SELECT MAX(eventOrdinal) FROM connection_session_location_events WHERE sessionID = s.id) AS lastOrdinal
        FROM connection_sessions s
        LEFT JOIN connection_session_location_track_sync_states st ON st.sessionID = s.id
        WHERE s.accountIdentifier = ? AND s.endedAt IS NOT NULL
          AND (st.origin IS NULL OR st.origin = '\(ConnectionSessionLocationTrackSyncOrigin.uploaded.rawValue)')
          AND (EXISTS (SELECT 1 FROM connection_session_location_samples WHERE sessionID = s.id)
               OR EXISTS (SELECT 1 FROM connection_session_location_events WHERE sessionID = s.id))
        ORDER BY s.startedAt, s.id
        """

    /// 候補を読み取ります。
    ///
    /// 責務: 1回の読取接続で、候補のセッションごとにローカル水位と同期記録を添えて返します。
    /// - Parameters:
    ///   - accountIdentifier: 対象のアカウント識別子。
    ///   - database: 読取中のSQLite接続。
    /// - Returns: 候補の一覧。
    /// - Throws: 読取失敗はGRDBエラー、復元不能な保存値は `.integrityConflict`。
    func candidates(
        for accountIdentifier: String,
        in database: Database
    ) throws -> [ConnectionSessionLocationTrackUploadCandidate] {
        let rows = try Row.fetchAll(database, sql: Self.sql, arguments: [accountIdentifier])
        return try rows.map { row in
            let key: String = row["id"]
            guard let uuid = UUID(uuidString: key) else { throw ConnectionSessionRepositoryError.integrityConflict }
            let record = try ConnectionSessionLocationTrackSyncStateRecord.fetchOne(database, key: key)
            return ConnectionSessionLocationTrackUploadCandidate(
                sessionID: ConnectionSessionID(rawValue: uuid),
                localWatermark: ConnectionSessionLocationTrackWatermark(
                    sampleCount: row["sampleCount"],
                    lastSampleSequence: row["lastSequence"],
                    eventCount: row["eventCount"],
                    lastEventOrdinal: row["lastOrdinal"]
                ),
                syncRecord: try record?.makeDomainRecord()
            )
        }
    }
}
