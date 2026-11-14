import Foundation
import GRDB

/// GRDB/SQLiteへ受信CANフレームを保存します。
nonisolated final class GRDBConnectionSessionCANFrameRepository: ConnectionSessionCANFrameRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue
    /// GRDBの失敗をRepositoryの失敗理由へ変換します。
    private let errorTranslator = GRDBConnectionSessionSegmentationErrorTranslator()

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続をCANフレームスキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: CANフレームを保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// CANフレーム配列を1件のまとまりとして保存します。
    ///
    /// 責務: 採番済みフレーム配列を1回のSQLite transaction内で一括insertし、途中失敗時は全件を巻き戻します。
    /// - Parameters:
    ///   - frames: 呼び出し側が採番した保存対象フレーム。
    ///   - sessionID: フレームを所有する接続セッション。
    /// - Throws: 制約違反と範囲外の値は `.integrityConflict`、それ以外の保存失敗は `.unavailable`。
    func saveFrames(_ frames: [CANFrameObservation], for sessionID: ConnectionSessionID) throws {
        do {
            let records = try frames.map { try ConnectionSessionCANFrameRecord(frame: $0, sessionID: sessionID) }
            try databaseQueue.write { database in
                for record in records {
                    try record.insert(database)
                }
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }

    /// セッションのCANフレームを記録順で返します。
    ///
    /// 責務: 1件のセッションに属するSQLite行を記録順序昇順でDomainへ復元します。
    /// - Parameter sessionID: 読取対象の接続セッション。
    /// - Returns: `sequence` 昇順のフレーム。
    /// - Throws: 復元できない保存値は `.integrityConflict`、それ以外の読取失敗は `.unavailable`。
    func frames(for sessionID: ConnectionSessionID) throws -> [CANFrameObservation] {
        do {
            return try databaseQueue.read { database in
                try ConnectionSessionCANFrameRecord
                    .filter(Column("sessionID") == sessionID.rawValue.uuidString.lowercased())
                    .order(Column("sequence"))
                    .fetchAll(database)
                    .map { try $0.makeDomainFrame() }
            }
        } catch {
            throw errorTranslator.repositoryError(for: error)
        }
    }
}
