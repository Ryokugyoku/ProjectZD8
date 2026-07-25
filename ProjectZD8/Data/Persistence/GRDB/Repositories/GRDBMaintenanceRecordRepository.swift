import Foundation
import GRDB

/// GRDB/SQLiteへ写真を含む車両別整備記録を保存します。
final class GRDBMaintenanceRecordRepository: MaintenanceRecordRepository, @unchecked Sendable {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続を整備記録スキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: 整備記録を保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ProjectZD8DatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// Application Support内の製品DBを開いて生成します。
    ///
    /// 責務: 整備記録の製品保存先を作成してRepositoryを返します。
    /// - Returns: Migration済みの整備記録Repository。
    /// - Throws: 保存先作成、DB接続、Migrationに失敗した場合のエラー。
    static func openApplicationRepository() throws -> GRDBMaintenanceRecordRepository {
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
        return try GRDBMaintenanceRecordRepository(databaseQueue: queue)
    }

    /// 指定アカウントの全整備記録を更新日時順で取得します。
    ///
    /// 責務: 1件のアカウントに属するSQLite行をDomain整備記録へ復元します。
    /// - Parameter accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Returns: 墓石を含む全整備記録。
    /// - Throws: SQLite読込または復号に失敗した場合のエラー。
    func records(for accountIdentifier: String) async throws -> [MaintenanceRecord] {
        try await databaseQueue.read { database in
            try MaintenanceRecordRecord
                .filter(Column("accountIdentifier") == accountIdentifier)
                .order(Column("updatedAt").desc)
                .fetchAll(database)
                .map { try $0.makeDomainRecord() }
        }
    }

    /// 指定アカウントへ整備記録を作成または更新します。
    ///
    /// 責務: 1件のDomain整備記録をSQLiteへupsertします。
    /// - Parameters:
    ///   - record: 保存する整備記録。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Throws: 符号化またはSQLite書込に失敗した場合のエラー。
    func save(_ record: MaintenanceRecord, for accountIdentifier: String) async throws {
        let stored = try MaintenanceRecordRecord(record: record, accountIdentifier: accountIdentifier)
        try await databaseQueue.write { database in
            try stored.save(database)
        }
    }

    /// 同期済み集合で指定アカウントの整備記録を置き換えます。
    ///
    /// 責務: 1件のアカウントに属する全整備行を1トランザクションで更新します。
    /// - Parameters:
    ///   - records: 墓石を含む同期済み記録集合。
    ///   - accountIdentifier: Appleアカウントのアプリ固有識別子。
    /// - Throws: 符号化またはSQLiteトランザクションに失敗した場合のエラー。
    func replaceAll(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        let stored = try records.map { try MaintenanceRecordRecord(record: $0, accountIdentifier: accountIdentifier) }
        try await databaseQueue.write { database in
            try MaintenanceRecordRecord
                .filter(Column("accountIdentifier") == accountIdentifier)
                .deleteAll(database)
            for record in stored {
                try record.insert(database)
            }
        }
    }
}
