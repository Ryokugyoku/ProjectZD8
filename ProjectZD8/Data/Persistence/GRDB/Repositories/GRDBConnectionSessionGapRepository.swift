import Foundation
import GRDB

/// GRDB/SQLiteへ連続取得区間の間の空白を保存します。
nonisolated final class GRDBConnectionSessionGapRepository: ConnectionSessionGapRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// GRDBの失敗をRepositoryの失敗理由へ変換します。
    private let errorTranslator = GRDBConnectionSessionSegmentationErrorTranslator()

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続を欠損スキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: 取得の空白を保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// 取得の空白を新規保存します。
    ///
    /// 責務: 1件の空白を指定セッションへinsertします。
    /// - Parameters:
    ///   - gap: 保存する空白。
    ///   - sessionID: 空白を所有する接続セッション。
    /// - Throws: 制約違反と範囲外の値は `.integrityConflict`、それ以外の保存失敗は `.unavailable`。
    func saveGap(_ gap: ConnectionSessionGap, for sessionID: ConnectionSessionID) throws {
        do {
            let record = try ConnectionSessionGapRecord(gap: gap, sessionID: sessionID)
            try databaseQueue.write { database in
                try record.insert(database)
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// 未終了の空白へ終了時刻と直後の区間を確定します。
    ///
    /// 責務: 1件の未終了の空白の終了時刻と後続区間番号を1回のtransactionで更新します。
    /// - Parameters:
    ///   - gapOrdinal: 終了する空白の番号。
    ///   - sessionID: 空白を所有する接続セッション。
    ///   - endedAt: 空白が終わった実時間。
    ///   - followingSegmentOrdinal: 空白の直後に始まった区間の番号。再開せずに終わる場合は `nil`。
    /// - Throws: 空白不在または終了済みは `.invalidState`、制約違反は `.integrityConflict`、
    ///   それ以外の保存失敗は `.unavailable`。
    func finishGap(
        ordinal gapOrdinal: Int,
        for sessionID: ConnectionSessionID,
        endedAt: Date,
        followingSegmentOrdinal: Int?
    ) throws {
        do {
            let endedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: endedAt)
            try databaseQueue.write { database in
                let openGap = ConnectionSessionGapRecord
                    .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                    .filter(Column("gapOrdinal") == gapOrdinal)
                    .filter(Column("endedAtMicroseconds") == nil)
                let updatedCount = try openGap.updateAll(
                    database,
                    Column("endedAtMicroseconds").set(to: endedAtMicroseconds),
                    Column("followingSegmentOrdinal").set(to: followingSegmentOrdinal)
                )
                guard updatedCount == 1 else {
                    throw ConnectionSessionRepositoryError.invalidState
                }
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// セッションの空白を欠損番号順で返します。
    ///
    /// 責務: 1件のセッションに属するSQLite行を欠損番号昇順でDomainへ復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `gapOrdinal` 昇順の空白。
    /// - Throws: 復元できない保存値は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func gaps(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionGap] {
        do {
            return try databaseQueue.read { database in
                try ConnectionSessionGapRecord
                    .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                    .order(Column("gapOrdinal"))
                    .fetchAll(database)
                    .map { try $0.makeDomainGap() }
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }
}
