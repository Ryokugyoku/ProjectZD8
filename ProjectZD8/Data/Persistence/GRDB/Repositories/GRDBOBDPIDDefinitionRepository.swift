import Foundation
import GRDB

/// GRDB/SQLiteへPID変換定義を保存します。
final class GRDBOBDPIDDefinitionRepository: OBDPIDDefinitionRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue

    /// 指定DB Queueへ製品版初期Migrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続を製品版スキーマ利用可能状態へ移行してPID定義Repositoryを生成します。
    /// - Parameter databaseQueue: PID定義を保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// Application Support内の製品DBを開いて生成します。
    ///
    /// 責務: PID定義DBの製品保存先を作成してリポジトリを返します。
    /// - Returns: Migration済みのPID定義リポジトリ。
    /// - Throws: 保存先作成、DB接続、Migrationに失敗した場合のエラー。
    static func openApplicationRepository() throws -> GRDBOBDPIDDefinitionRepository {
        let fileManager = FileManager.default
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(path: "ProjectZD8", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: directory.appending(path: "projectzd8.sqlite").path)
        return try GRDBOBDPIDDefinitionRepository(databaseQueue: queue)
    }

    /// 登録済みの現在PID定義を識別子順で取得します。
    ///
    /// 責務: PIDテーブルの全レコードをService/PIDの昇順でDomain定義へ復元します。
    /// - Returns: 登録済みPID定義の一覧。
    /// - Throws: SQLite読込または不正な列値の場合のエラー。
    func definitions() throws -> [OBDPIDDefinition] {
        try databaseQueue.read { database in
            let records = try OBDPIDDefinitionRecord
                .order(Column("service"), Column("pid"))
                .fetchAll(database)
            return try records.map { record in
                guard let definition = record.makeDomainDefinition() else {
                    throw DatabaseError(message: "PID definition contains an out-of-range identifier")
                }
                return definition
            }
        }
    }

    /// 定義の改訂番号が新しい場合だけ登録または更新します。
    ///
    /// 責務: 1件のPID定義を既存改訂を後退させずSQLiteへ保存します。
    /// - Parameter definition: 保存するPID定義。
    /// - Throws: SQLite書込みまたは制約確認に失敗した場合のGRDBエラー。
    func upsert(_ definition: OBDPIDDefinition) throws {
        try databaseQueue.write { database in
            let record = OBDPIDDefinitionRecord(definition: definition)
            let currentRevision = try Int.fetchOne(
                database,
                sql: "SELECT revision FROM obd_pid_definitions WHERE service = ? AND pid = ?",
                arguments: [record.service, record.pid]
            )
            guard currentRevision == nil || definition.revision > currentRevision! else { return }
            try record.save(database)
        }
    }

    /// 指定Service/PIDの現在定義を取得します。
    ///
    /// 責務: 1件の複合識別子に一致するPID定義をSQLiteから復元します。
    /// - Parameters:
    ///   - service: OBD Service番号。
    ///   - pid: Service内PID番号。
    /// - Returns: 登録済みDomain定義。未登録の場合は `nil`。
    /// - Throws: SQLite読込または不正な列値の場合のエラー。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? {
        try databaseQueue.read { database in
            let record = try OBDPIDDefinitionRecord.fetchOne(
                database,
                key: ["service": Int(service), "pid": Int(pid)]
            )
            guard let record else { return nil }
            guard let definition = record.makeDomainDefinition() else {
                throw DatabaseError(message: "PID definition contains an out-of-range identifier")
            }
            return definition
        }
    }
}
