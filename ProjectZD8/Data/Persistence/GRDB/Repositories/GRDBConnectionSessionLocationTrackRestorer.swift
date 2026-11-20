import Foundation
import GRDB

/// iCloudから取得した軌跡でローカルの軌跡行を置き換えます。
nonisolated struct GRDBConnectionSessionLocationTrackRestorer {
    /// 軌跡を置き換えます。
    ///
    /// 責務: 呼び出し元の書込みtransactionの中で、この端末で記録した行が無いことを確かめ、
    /// 既存の軌跡行を消して番号どおりに入れ直し、origin = restored の同期記録を保存します。
    /// - Parameters:
    ///   - verified: digest照合済みの軌跡。
    ///   - date: 同期した時刻。
    ///   - database: 書込み中のSQLite接続。
    /// - Throws: セッション不在・この端末で記録した行がある場合は `.integrityConflict`、その他はGRDBエラー。
    func replace(_ verified: VerifiedConnectionSessionLocationTrack, at date: Date, in database: Database) throws {
        let sessionID = verified.track.sessionID
        let key = sessionID.rawValue.uuidString.lowercased()
        try requireSession(key, in: database)
        try requireNoLocallyRecordedRows(key, in: database)
        try database.execute(sql: "DELETE FROM connection_session_location_samples WHERE sessionID = ?", arguments: [key])
        try database.execute(sql: "DELETE FROM connection_session_location_events WHERE sessionID = ?", arguments: [key])
        try insertRows(of: verified.track, in: database)
        try ConnectionSessionLocationTrackSyncStateRecord(
            ConnectionSessionLocationTrackSyncRecord(
                sessionID: sessionID,
                origin: .restored,
                manifestDigest: verified.manifestDigest,
                watermark: verified.track.watermark,
                syncedAt: date
            )
        ).save(database)
    }

    /// 軌跡の行を挿入します。
    ///
    /// 責務: サンプルと事象を、軌跡の番号のままinsertします。
    private func insertRows(of track: ConnectionSessionLocationTrack, in database: Database) throws {
        for sample in track.samples {
            try ConnectionSessionLocationSampleRecord(fix: sample.fix, sequence: sample.sequence, sessionID: track.sessionID)
                .insert(database)
        }
        for event in track.events {
            try ConnectionSessionLocationEventRecord(
                kind: event.kind,
                ordinal: Int64(event.ordinal),
                occurredAt: event.occurredAt,
                sessionID: track.sessionID
            ).insert(database)
        }
    }

    /// 親セッションの存在を確かめます。
    ///
    /// 責務: セッション行が無ければ整合性エラーにします。
    private func requireSession(_ key: String, in database: Database) throws {
        let exists = try ConnectionSessionRecord.filter(Column("id") == key).fetchCount(database) > 0
        guard exists else { throw ConnectionSessionRepositoryError.integrityConflict }
    }

    /// この端末で記録した行が無いことを確かめます。
    ///
    /// 責務: サンプルか事象の行があり、同期記録が無いか uploaded の場合は整合性エラーにします。
    private func requireNoLocallyRecordedRows(_ key: String, in database: Database) throws {
        let origin = try ConnectionSessionLocationTrackSyncStateRecord.fetchOne(database, key: key)?.origin
        guard origin != ConnectionSessionLocationTrackSyncOrigin.restored.rawValue else { return }
        let hasSamples = try ConnectionSessionLocationSampleRecord.filter(Column("sessionID") == key).fetchCount(database) > 0
        let hasEvents = try ConnectionSessionLocationEventRecord.filter(Column("sessionID") == key).fetchCount(database) > 0
        guard !hasSamples, !hasEvents else { throw ConnectionSessionRepositoryError.integrityConflict }
    }
}
