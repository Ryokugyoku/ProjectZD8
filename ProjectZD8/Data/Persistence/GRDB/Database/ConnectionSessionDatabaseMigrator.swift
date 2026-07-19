import GRDB

/// 接続セッション履歴テーブルのスキーマ改訂を定義します。
enum ConnectionSessionDatabaseMigrator {
    /// 現在アプリが知る全接続セッションMigrationです。
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v2_create_connection_sessions") { database in
            try database.create(table: ConnectionSessionRecord.databaseTableName) { table in
                table.column("id", .text).primaryKey().notNull()
                    .check { length($0) > 0 }
                table.column("accountIdentifier", .text).notNull()
                    .check { length($0) > 0 }
                table.column("startedAt", .datetime).notNull()
                table.column("endedAt", .datetime)
                table.column("endReason", .text)
                table.column("vehicleID", .text)
                table.column("vehicleName", .text)
                table.column("vehicleDisplayIdentifier", .text)
                table.check(sql: "(endedAt IS NULL AND endReason IS NULL) OR (endedAt IS NOT NULL AND endReason IS NOT NULL)")
                table.check(sql: "(vehicleID IS NULL AND vehicleName IS NULL AND vehicleDisplayIdentifier IS NULL) OR (vehicleID IS NOT NULL AND vehicleName IS NOT NULL AND vehicleDisplayIdentifier IS NOT NULL)")
            }
            try database.create(
                index: "connection_sessions_account_started_at",
                on: ConnectionSessionRecord.databaseTableName,
                columns: ["accountIdentifier", "startedAt"]
            )
        }
        return migrator
    }
}
