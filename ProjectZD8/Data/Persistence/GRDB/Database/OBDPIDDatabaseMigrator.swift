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
        migrator.registerMigration("v2_expand_pid_catalog_and_vehicle_capabilities") { database in
            try database.rename(table: OBDPIDDefinitionRecord.databaseTableName, to: "obd_pid_definitions_v1")
            try createDefinitionTable(in: database)
            try database.execute(sql: """
                INSERT INTO obd_pid_definitions
                    (service, pid, nameKey, requiredByteCount, formula, unit, minimumValue, maximumValue,
                     sourceURI, revision, summaryKey, highValueKey, lowValueKey, correlationKey)
                SELECT service, pid, nameKey, requiredByteCount, formula, unit, minimumValue, maximumValue,
                       sourceURI, revision,
                       'obd.pid.help.unconfirmed.summary', 'obd.pid.help.unconfirmed.high',
                       'obd.pid.help.unconfirmed.low', 'obd.pid.help.unconfirmed.correlation'
                FROM obd_pid_definitions_v1
                """)
            try database.drop(table: "obd_pid_definitions_v1")
            try database.create(table: VehiclePIDCapabilityRecord.databaseTableName) { table in
                table.column("vehicleID", .text).notNull().collate(.nocase)
                table.column("service", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
                table.column("pid", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
                table.column("isCollectionEnabled", .boolean).notNull().defaults(to: true)
                table.column("discoveredAt", .datetime).notNull()
                table.primaryKey(["vehicleID", "service", "pid"])
            }
        }
        return migrator
    }

    /// 拡張メタデータと未確認式を許容するPID定義表を作成します。
    ///
    /// 責務: 現行PIDカタログの列制約を1件のSQLiteテーブルへ固定します。
    /// - Parameter database: テーブルを作成するSQLite接続。
    /// - Throws: テーブル作成に失敗した場合のGRDBエラー。
    nonisolated private static func createDefinitionTable(in database: Database) throws {
        try database.create(table: OBDPIDDefinitionRecord.databaseTableName) { table in
            table.column("service", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
            table.column("pid", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
            table.column("nameKey", .text).notNull().check { length($0) > 0 }
            table.column("requiredByteCount", .integer).check { $0 >= 1 && $0 <= 8 }
            table.column("formula", .text)
            table.column("unit", .text).notNull()
            table.column("minimumValue", .double)
            table.column("maximumValue", .double)
            table.column("sourceURI", .text).notNull().check { length($0) > 0 }
            table.column("revision", .integer).notNull().check { $0 >= 1 }
            table.column("summaryKey", .text).notNull()
            table.column("highValueKey", .text).notNull()
            table.column("lowValueKey", .text).notNull()
            table.column("correlationKey", .text).notNull()
            table.primaryKey(["service", "pid"])
            table.check(sql: "(requiredByteCount IS NULL AND formula IS NULL) OR (requiredByteCount IS NOT NULL AND formula IS NOT NULL AND length(formula) > 0)")
            table.check(sql: "(minimumValue IS NULL AND maximumValue IS NULL) OR (minimumValue IS NOT NULL AND maximumValue IS NOT NULL AND minimumValue <= maximumValue)")
        }
    }
}
