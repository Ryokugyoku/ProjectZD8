import Foundation
import GRDB

/// GRDB/SQLiteへ接続セッション履歴を保存します。
final class GRDBConnectionSessionRepository: ConnectionSessionRepository {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue

    /// 指定DB QueueへMigrationを適用して生成します。
    ///
    /// 責務: 1件のSQLite接続をセッション履歴スキーマ利用可能状態へ移行します。
    /// - Parameter databaseQueue: 接続セッションを保存するDB Queue。
    /// - Throws: Migrationを完了できない場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try ConnectionSessionDatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// Application Support内の製品DBを開いて生成します。
    ///
    /// 責務: 接続セッションDBの製品保存先を作成してリポジトリを返します。
    /// - Returns: Migration済みの接続セッションリポジトリ。
    /// - Throws: 保存先作成、DB接続、Migrationに失敗した場合のエラー。
    static func openApplicationRepository() throws -> GRDBConnectionSessionRepository {
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
        return try GRDBConnectionSessionRepository(databaseQueue: queue)
    }

    /// セッションの現在内容を安定ID単位で保存します。
    ///
    /// 責務: 1件のDomain接続セッションをGRDBへ新規保存または更新します。
    /// - Parameter session: 保存する接続セッション。
    /// - Throws: SQLite書込みまたは制約確認に失敗した場合のGRDBエラー。
    func save(_ session: ConnectionSession) throws {
        try databaseQueue.write { database in
            try ConnectionSessionRecord(session: session).save(database)
        }
    }

    /// 指定アカウントの接続セッションを新しい順で復元します。
    ///
    /// 責務: 1件のアカウント識別子に一致するGRDBレコードをDomain履歴へ復元します。
    /// - Parameter accountIdentifier: 取得対象のAppleアカウント識別子。
    /// - Returns: 開始日時が新しい順の接続セッション一覧。
    /// - Throws: SQLite読込または不正な保存値の場合のエラー。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] {
        try databaseQueue.read { database in
            let records = try ConnectionSessionRecord
                .filter(Column("accountIdentifier") == accountIdentifier)
                .order(Column("startedAt").desc)
                .fetchAll(database)
            return try records.map { record in
                guard let session = record.makeDomainSession() else {
                    throw DatabaseError(message: "Connection session contains an invalid identifier or end reason")
                }
                return session
            }
        }
    }
}
