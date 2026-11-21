import Foundation
import GRDB

/// GRDB/SQLiteへ接続セッションの位置サンプルと位置記録事象を保存します。
nonisolated final class GRDBConnectionSessionLocationRepository: ConnectionSessionLocationRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// GRDBの失敗をRepositoryの失敗理由へ変換します。
    private let errorTranslator = GRDBConnectionSessionSegmentationErrorTranslator()

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続を位置スキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: 位置を保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// 位置を1点追記します。
    ///
    /// 責務: 同じ書込みtransactionの中で連番を最大値+1(初回は0)で採番して位置をinsertします。
    /// - Parameters:
    ///   - fix: 保存する位置。
    ///   - sessionID: 位置を所有する接続セッション。
    /// - Throws: セッション不在・制約違反は `.integrityConflict`、それ以外の保存失敗は `.unavailable`。
    func appendSample(_ fix: LocationFix, for sessionID: ConnectionSessionID) throws {
        do {
            let key = sessionID.rawValue.uuidString.lowercased()
            try databaseQueue.write { database in
                try requireSession(key, in: database)
                let sequence = try nextNumber(
                    table: ConnectionSessionLocationSampleRecord.databaseTableName,
                    column: "sequence",
                    sessionKey: key,
                    in: database
                )
                try ConnectionSessionLocationSampleRecord(fix: fix, sequence: sequence, sessionID: sessionID)
                    .insert(database)
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// セッションの位置を連番順で返します。
    ///
    /// 責務: 1件のセッションに属するSQLite行を連番昇順でDomainへ復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `sequence` 昇順の位置。
    /// - Throws: 復元できない保存値は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func samples(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationSample] {
        do {
            return try databaseQueue.read { database in
                try ConnectionSessionLocationSampleRecord
                    .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                    .order(Column("sequence"))
                    .fetchAll(database)
                    .map { try $0.makeDomainSample() }
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// 位置記録の状態変化を1件追記します。
    ///
    /// 責務: 同じ書込みtransactionの中で事象番号を最大値+1(初回は0)で採番して事象をinsertします。
    /// - Parameters:
    ///   - kind: 状態の種類。
    ///   - occurredAt: 状態が変化した実時間。
    ///   - sessionID: 状態変化を所有する接続セッション。
    /// - Throws: セッション不在・制約違反は `.integrityConflict`、それ以外の保存失敗は `.unavailable`。
    func appendEvent(
        _ kind: ConnectionSessionLocationEventKind,
        occurredAt: Date,
        for sessionID: ConnectionSessionID
    ) throws {
        do {
            let key = sessionID.rawValue.uuidString.lowercased()
            try databaseQueue.write { database in
                try requireSession(key, in: database)
                let ordinal = try nextNumber(
                    table: ConnectionSessionLocationEventRecord.databaseTableName,
                    column: "eventOrdinal",
                    sessionKey: key,
                    in: database
                )
                try ConnectionSessionLocationEventRecord(
                    kind: kind,
                    ordinal: ordinal,
                    occurredAt: occurredAt,
                    sessionID: sessionID
                ).insert(database)
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// セッションの位置記録の状態変化を事象番号順で返します。
    ///
    /// 責務: 1件のセッションに属するSQLite行を事象番号昇順でDomainへ復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `ordinal` 昇順の状態変化。
    /// - Throws: 復元できない保存値は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func events(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionLocationEvent] {
        do {
            return try databaseQueue.read { database in
                try ConnectionSessionLocationEventRecord
                    .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                    .order(Column("eventOrdinal"))
                    .fetchAll(database)
                    .map { try $0.makeDomainEvent() }
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// 親セッションの存在を確かめます。
    ///
    /// 責務: セッション行が無ければ整合性エラーにして、孤児行の追加を拒否します。
    /// - Parameters:
    ///   - sessionKey: 小文字UUID文字列のセッションID。
    ///   - database: 書込み中のSQLite接続。
    /// - Throws: セッション不在は `.integrityConflict`、読取失敗はGRDBエラー。
    private func requireSession(_ sessionKey: String, in database: Database) throws {
        let exists = try ConnectionSessionRecord
            .filter(Column("id") == sessionKey)
            .fetchCount(database) > 0
        guard exists else { throw ConnectionSessionRepositoryError.integrityConflict }
    }

    /// セッション内の次の番号を返します。
    ///
    /// 責務: 指定表のセッション内最大番号に1を足した値(行が無ければ0)を返します。
    /// - Parameters:
    ///   - table: 採番対象の表名(定数のみを渡す)。
    ///   - column: 番号の列名(定数のみを渡す)。
    ///   - sessionKey: 小文字UUID文字列のセッションID。
    ///   - database: 書込み中のSQLite接続。
    /// - Returns: 次の番号。
    /// - Throws: 読取失敗はGRDBエラー。
    private func nextNumber(table: String, column: String, sessionKey: String, in database: Database) throws -> Int64 {
        let maximum = try Int64.fetchOne(
            database,
            sql: "SELECT MAX(\(column)) FROM \(table) WHERE sessionID = ?",
            arguments: [sessionKey]
        )
        return maximum.map { $0 + 1 } ?? 0
    }
}
