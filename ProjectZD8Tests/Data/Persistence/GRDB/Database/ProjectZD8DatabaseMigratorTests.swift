import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 製品版初期スキーマの一括作成と再適用安全性を検証します。
@MainActor
final class ProjectZD8DatabaseMigratorTests: XCTestCase {
    /// 空DBへ製品版1.0の全テーブルを単一Migrationで作成します。
    ///
    /// 責務: 単一Migrationが全GRDB Repositoryの必須テーブルを作成することを確認します。
    func testReleaseBaselineCreatesAllProductTables() throws {
        let queue = try DatabaseQueue()

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            XCTAssertTrue(try database.tableExists(OBDPIDDefinitionRecord.databaseTableName))
            XCTAssertTrue(try database.tableExists(VehiclePIDCapabilityRecord.databaseTableName))
            XCTAssertTrue(try database.tableExists(ConnectionSessionRecord.databaseTableName))
            XCTAssertTrue(try database.tableExists(ConnectionSessionRawLogRecord.databaseTableName))
            XCTAssertTrue(try database.tableExists(MaintenanceRecordRecord.databaseTableName))
        }
    }

    /// 製品版初期Migrationの識別子を1件だけ登録します。
    ///
    /// 責務: 開発途中の段階Migrationが製品版Migratorへ残っていないことを確認します。
    func testReleaseBaselineContainsSingleMigration() {
        XCTAssertEqual(ProjectZD8DatabaseMigrator.migrator.migrations, ["release_v1_create_schema"])
    }

    /// 旧開発Migrationで作成済みの運転データを保持して現行スキーマへ移行します。
    ///
    /// 責務: 旧Migration履歴を持つDBへ現行Migrationを適用して既存セッション保持と整備表追加を確認します。
    func testReleaseBaselinePreservesLegacySessionSchemaAndAddsMaintenanceTable() throws {
        let queue = try DatabaseQueue()
        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)
        try queue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO connection_sessions
                        (id, accountIdentifier, startedAt, endedAt, endReason)
                    VALUES ('legacy-session', 'account', ?, ?, 'userDisconnected')
                    """,
                arguments: [
                    Date(timeIntervalSince1970: 100),
                    Date(timeIntervalSince1970: 101)
                ]
            )
            try database.drop(table: MaintenanceRecordRecord.databaseTableName)
            try database.execute(sql: "DELETE FROM grdb_migrations")
            try database.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["v8_add_connection_session_raw_last_accessed_at"]
            )
        }

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            let sessionCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM connection_sessions WHERE id = 'legacy-session'"
            )
            XCTAssertEqual(sessionCount, 1)
            XCTAssertTrue(try database.tableExists(MaintenanceRecordRecord.databaseTableName))
            XCTAssertEqual(
                try String.fetchAll(database, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"),
                ["release_v1_create_schema", "v8_add_connection_session_raw_last_accessed_at"]
            )
        }
    }

    /// 同じ製品版初期Migrationを複数回適用しても既存データを保持します。
    ///
    /// 責務: RepositoryごとのMigration呼出しが作成済みテーブルと保存値を変更しないことを確認します。
    func testReleaseBaselineIsIdempotentAfterCompletion() throws {
        let queue = try DatabaseQueue()
        let migrator = ProjectZD8DatabaseMigrator.migrator
        try migrator.migrate(queue)
        try queue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO vehicle_pid_capabilities
                        (vehicleID, service, pid, isCollectionEnabled, discoveredAt)
                    VALUES ('vehicle', 1, 12, 1, ?)
                    """,
                arguments: [Date(timeIntervalSince1970: 100)]
            )
        }

        try migrator.migrate(queue)

        let count = try queue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM vehicle_pid_capabilities")
        }
        XCTAssertEqual(count, 1)
    }
}
