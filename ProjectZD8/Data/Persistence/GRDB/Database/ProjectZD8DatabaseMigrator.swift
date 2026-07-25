import GRDB

/// 製品DBの現行SQLiteスキーマと旧開発DBの非破壊移行を定義します。
enum ProjectZD8DatabaseMigrator {
    /// 製品版1.0の全テーブルを不足分だけ作成する単一Migrationです。
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("release_v1_create_schema") { database in
            if try !database.tableExists(OBDPIDDefinitionRecord.databaseTableName) {
                try createOBDPIDDefinitions(in: database)
            }
            if try !database.tableExists(VehiclePIDCapabilityRecord.databaseTableName) {
                try createVehiclePIDCapabilities(in: database)
            }
            if try !database.tableExists(ConnectionSessionRecord.databaseTableName) {
                try createConnectionSessions(in: database)
            }
            if try !database.tableExists(ConnectionSessionRawLogRecord.databaseTableName) {
                try createConnectionSessionRawLogs(in: database)
            }
            if try !database.tableExists(MaintenanceRecordRecord.databaseTableName) {
                try createMaintenanceRecords(in: database)
            }
        }
        return migrator
    }

    /// 現行メタデータと車種適用範囲を持つPID定義表を作成します。
    ///
    /// 責務: 製品版1.0のPID定義列と制約を1件のSQLiteテーブルへ固定します。
    /// - Parameter database: テーブルを作成するSQLite接続。
    /// - Throws: テーブル作成に失敗した場合のGRDBエラー。
    nonisolated private static func createOBDPIDDefinitions(in database: Database) throws {
        try database.create(table: OBDPIDDefinitionRecord.databaseTableName) { table in
            table.column("service", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
            table.column("pid", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
            table.column("header", .integer)
            table.column("vehicleModelCode", .text)
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
            table.check(sql: "(header IS NULL AND vehicleModelCode IS NULL) OR (header IS NOT NULL AND vehicleModelCode IS NOT NULL)")
            table.check(sql: "(requiredByteCount IS NULL AND formula IS NULL) OR (requiredByteCount IS NOT NULL AND formula IS NOT NULL AND length(formula) > 0)")
            table.check(sql: "(minimumValue IS NULL AND maximumValue IS NULL) OR (minimumValue IS NOT NULL AND maximumValue IS NOT NULL AND minimumValue <= maximumValue)")
        }
    }

    /// 車両別PID対応状況と収集選択を保持する表を作成します。
    ///
    /// 責務: 製品版1.0の車両別PID能力を1件のSQLiteテーブルへ固定します。
    /// - Parameter database: テーブルを作成するSQLite接続。
    /// - Throws: テーブル作成に失敗した場合のGRDBエラー。
    nonisolated private static func createVehiclePIDCapabilities(in database: Database) throws {
        try database.create(table: VehiclePIDCapabilityRecord.databaseTableName) { table in
            table.column("vehicleID", .text).notNull().collate(.nocase)
            table.column("service", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
            table.column("pid", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
            table.column("isCollectionEnabled", .boolean).notNull().defaults(to: true)
            table.column("discoveredAt", .datetime).notNull()
            table.primaryKey(["vehicleID", "service", "pid"])
        }
    }

    /// 接続履歴、車両スナップショット、転送状態を保持する表を作成します。
    ///
    /// 責務: 製品版1.0の接続セッション列と検索索引を1件のSQLiteテーブルへ固定します。
    /// - Parameter database: テーブルを作成するSQLite接続。
    /// - Throws: テーブルまたは索引の作成に失敗した場合のGRDBエラー。
    nonisolated private static func createConnectionSessions(in database: Database) throws {
        try database.create(table: ConnectionSessionRecord.databaseTableName) { table in
            table.column("id", .text).primaryKey().notNull().check { length($0) > 0 }
            table.column("accountIdentifier", .text).notNull().check { length($0) > 0 }
            table.column("startedAt", .datetime).notNull()
            table.column("endedAt", .datetime)
            table.column("endReason", .text)
            table.column("stopReviewDecision", .text)
            table.column("vehicleID", .text)
            table.column("vehicleName", .text)
            table.column("vehicleDisplayIdentifier", .text)
            table.column("acquisitionPlatform", .text)
            table.column("acquisitionDeviceName", .text)
            table.column("startingOdometerKilometers", .double)
            table.column("endingOdometerKilometers", .double)
            table.column("distanceSourceModelCode", .text)
            table.column("rawRecordCount", .integer).notNull().defaults(to: 0)
            table.column("rawByteCount", .integer).notNull().defaults(to: 0)
            table.column("localRawState", .text).notNull().defaults(to: ConnectionSessionLocalRawState.empty.rawValue)
            table.column("cloudSyncState", .text).notNull().defaults(to: ConnectionSessionCloudSyncState.notUploaded.rawValue)
            table.column("manifestDigest", .text)
            table.column("macImportedDeviceID", .text)
            table.column("macImportedDeviceName", .text)
            table.column("macImportedAt", .datetime)
            table.column("macImportedManifestDigest", .text)
            table.column("rawLastAccessedAt", .datetime)
            table.check(sql: "(endedAt IS NULL AND endReason IS NULL) OR (endedAt IS NOT NULL AND endReason IS NOT NULL)")
            table.check(sql: "(vehicleID IS NULL AND vehicleName IS NULL AND vehicleDisplayIdentifier IS NULL) OR (vehicleID IS NOT NULL AND vehicleName IS NOT NULL AND vehicleDisplayIdentifier IS NOT NULL)")
        }
        try database.create(
            index: "connection_sessions_account_started_at",
            on: ConnectionSessionRecord.databaseTableName,
            columns: ["accountIdentifier", "startedAt"]
        )
        try database.create(
            index: "connection_sessions_vehicle_started_at",
            on: ConnectionSessionRecord.databaseTableName,
            columns: ["accountIdentifier", "vehicleID", "startedAt"]
        )
    }

    /// セッション単位の未デコードOBD応答を保持する表を作成します。
    ///
    /// 責務: 製品版1.0のRawログ列、親子関係、検索索引を1件のSQLiteテーブルへ固定します。
    /// - Parameter database: テーブルを作成するSQLite接続。
    /// - Throws: テーブルまたは索引の作成に失敗した場合のGRDBエラー。
    nonisolated private static func createConnectionSessionRawLogs(in database: Database) throws {
        try database.create(table: ConnectionSessionRawLogRecord.databaseTableName) { table in
            table.column("sessionID", .text).notNull()
                .references(ConnectionSessionRecord.databaseTableName, column: "id", onDelete: .cascade)
            table.column("sequence", .integer).notNull().check { $0 >= 0 }
            table.column("observedAt", .datetime).notNull()
            table.column("batchElapsedNanoseconds", .integer).notNull().check { $0 >= 0 }
            table.column("service", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
            table.column("pid", .integer).notNull().check { $0 >= 0 && $0 <= 255 }
            table.column("payload", .blob).notNull()
            table.primaryKey(["sessionID", "sequence"])
        }
        try database.create(
            index: "connection_session_raw_logs_session_observed_at",
            on: ConnectionSessionRawLogRecord.databaseTableName,
            columns: ["sessionID", "observedAt"]
        )
    }

    /// 車両別整備記録と削除墓石を保持する表を作成します。
    ///
    /// 責務: 整備記録の検索列と完全JSONを1件のSQLiteテーブルへ固定します。
    /// - Parameter database: テーブルを作成するSQLite接続。
    /// - Throws: テーブルまたは索引の作成に失敗した場合のGRDBエラー。
    nonisolated private static func createMaintenanceRecords(in database: Database) throws {
        try database.create(table: MaintenanceRecordRecord.databaseTableName) { table in
            table.column("id", .text).primaryKey().notNull().check { length($0) > 0 }
            table.column("accountIdentifier", .text).notNull().check { length($0) > 0 }
            table.column("vehicleID", .text).notNull().check { length($0) > 0 }
            table.column("kind", .text).notNull().check { $0 == MaintenanceKind.light.rawValue || $0 == MaintenanceKind.heavy.rawValue }
            table.column("performedAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
            table.column("payload", .blob).notNull()
        }
        try database.create(
            index: "maintenance_records_account_vehicle_performed_at",
            on: MaintenanceRecordRecord.databaseTableName,
            columns: ["accountIdentifier", "vehicleID", "performedAt"]
        )
        try database.create(
            index: "maintenance_records_account_updated_at",
            on: MaintenanceRecordRecord.databaseTableName,
            columns: ["accountIdentifier", "updatedAt"]
        )
    }
}
