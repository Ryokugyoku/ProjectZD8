import Foundation
import GRDB

/// GRDB/SQLiteへ接続セッション内の連続取得区間を保存します。
nonisolated final class GRDBConnectionSessionSegmentRepository: ConnectionSessionSegmentRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// GRDBの失敗をRepositoryの失敗理由へ変換します。
    private let errorTranslator = GRDBConnectionSessionSegmentationErrorTranslator()

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続をセグメントスキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: 連続取得区間を保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// 未終了の連続取得区間を新規保存します。
    ///
    /// 責務: 1件の未終了区間を指定セッションへinsertします。
    /// - Parameters:
    ///   - segment: 終了情報を持たない開始時点の区間。
    ///   - sessionID: 区間を所有する接続セッション。
    /// - Throws: 終了情報を持つ区間は `.invalidState`、制約違反と範囲外の値は `.integrityConflict`、
    ///   それ以外の保存失敗は `.unavailable`。
    func beginSegment(_ segment: ConnectionSessionSegment, for sessionID: ConnectionSessionID) throws {
        guard segment.endedAt == nil, segment.endReason == nil, segment.lastSequence == nil else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        do {
            let record = try ConnectionSessionSegmentRecord(segment: segment, sessionID: sessionID)
            try databaseQueue.write { database in
                try record.insert(database)
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// 未終了の連続取得区間へ終了情報を確定します。
    ///
    /// 責務: 1件の未終了区間の終了時刻、終了理由、最終記録順序を1回のtransactionで更新します。
    /// - Parameters:
    ///   - segmentOrdinal: 終了する区間の番号。
    ///   - sessionID: 区間を所有する接続セッション。
    ///   - endedAt: 区間を終了した実時間。
    ///   - reason: 区間が終わった直接原因。
    ///   - lastSequence: 区間の最後の行の記録順序。行が1件もない場合は `nil`。
    /// - Throws: 区間不在または終了済みは `.invalidState`、制約違反は `.integrityConflict`、
    ///   それ以外の保存失敗は `.unavailable`。
    func finishSegment(
        ordinal segmentOrdinal: Int,
        for sessionID: ConnectionSessionID,
        endedAt: Date,
        reason: ConnectionSessionSegmentEndReason,
        lastSequence: Int64?
    ) throws {
        do {
            let endedAtMicroseconds = try ConnectionSessionMicrosecondTimestamp.microseconds(for: endedAt)
            try databaseQueue.write { database in
                let openSegment = ConnectionSessionSegmentRecord
                    .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                    .filter(Column("segmentOrdinal") == segmentOrdinal)
                    .filter(Column("endedAtMicroseconds") == nil)
                let updatedCount = try openSegment.updateAll(
                    database,
                    Column("endedAtMicroseconds").set(to: endedAtMicroseconds),
                    Column("endReason").set(to: reason.rawValue),
                    Column("lastSequence").set(to: lastSequence)
                )
                guard updatedCount == 1 else {
                    throw ConnectionSessionRepositoryError.invalidState
                }
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// セッションの連続取得区間を区間番号順で返します。
    ///
    /// 責務: 1件のセッションに属するSQLite行を区間番号昇順でDomainへ復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `segmentOrdinal` 昇順の区間。
    /// - Throws: 復元できない保存値は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func segments(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionSegment] {
        do {
            return try databaseQueue.read { database in
                try ConnectionSessionSegmentRecord
                    .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                    .order(Column("segmentOrdinal"))
                    .fetchAll(database)
                    .map { try $0.makeDomainSegment() }
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }
}
