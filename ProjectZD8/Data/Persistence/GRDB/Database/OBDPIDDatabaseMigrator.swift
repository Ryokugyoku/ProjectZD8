import GRDB

/// PID専用テーブルのスキーマ改訂を定義します。
enum OBDPIDDatabaseMigrator {
    /// 現在アプリが知る全PIDスキーマMigrationです。
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_obd_pid_definitions") { database in
            try database.create(table: OBDPIDDefinitionRecord.databaseTableName) { table in
                table.column("service", .integer).notNull()
                    .check { $0 >= 0 && $0 <= 255 }
                table.column("pid", .integer).notNull()
                    .check { $0 >= 0 && $0 <= 255 }
                table.column("nameKey", .text).notNull()
                    .check { length($0) > 0 }
                table.column("requiredByteCount", .integer).notNull()
                    .check { $0 >= 1 && $0 <= 8 }
                table.column("formula", .text).notNull()
                    .check { length($0) > 0 }
                table.column("unit", .text).notNull()
                table.column("minimumValue", .double)
                table.column("maximumValue", .double)
                table.column("sourceURI", .text).notNull()
                    .check { length($0) > 0 }
                table.column("revision", .integer).notNull()
                    .check { $0 >= 1 }
                table.primaryKey(["service", "pid"])
                table.check(
                    sql: "(minimumValue IS NULL AND maximumValue IS NULL) OR "
                        + "(minimumValue IS NOT NULL AND maximumValue IS NOT NULL AND minimumValue <= maximumValue)"
                )
            }
        }
        return migrator
    }
}
