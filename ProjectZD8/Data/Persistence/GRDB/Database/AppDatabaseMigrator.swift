import GRDB

/// 初版リリースのデータベーススキーマを定義します。
///
/// 規約:
/// - `…At` 列は全てUTCのUnixエポックからのミリ秒(INTEGER)です。
/// - ID列はUUIDの小文字文字列(TEXT)です。
/// - `deletedAt` が入った行は同期待ちの削除済み行で、リポジトリの照会結果には含めません。
/// - `session_pids` と `session_samples` は追記のみで、UPDATEをトリガーで禁止します。
nonisolated enum AppDatabaseMigrator {
    /// 現行スキーマを適用するマイグレーターです。リリース後の変更は新しいマイグレーションとして追加します。
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createVehicleTables(db)
            try createMaintenanceTables(db)
            try createSessionTables(db)
            try createSyncTables(db)
        }
        return migrator
    }

    /// 責務: 車両・写真・車両別PID設定のテーブルを作成します。
    private static func createVehicleTables(_ db: Database) throws {
        try db.create(table: "vehicles") { t in
            t.primaryKey("id", .text)
            t.column("vin", .text).notNull()
            t.column("obdIdentifier", .text)
            t.column("name", .text).notNull()
            t.column("manufacturer", .text).notNull()
            t.column("engineModel", .text).notNull()
            t.column("powertrain", .text).notNull()
            t.column("energySources", .text).notNull() // VehicleEnergySource.rawValue のJSON配列
            t.column("tankCapacityLiters", .double)
            t.column("modelYear", .integer)
            t.column("note", .text).notNull()
            t.column("photoID", .text)
            t.column("createdAt", .integer).notNull()
            t.column("modifiedAt", .integer).notNull()
            t.column("deletedAt", .integer)
        }
        try db.create(table: "photos") { t in
            t.primaryKey("id", .text) // 画像本体は Photos/<id>.jpg
            t.column("vehicleID", .text).notNull().indexed().references("vehicles", onDelete: .cascade)
            t.column("byteCount", .integer).notNull()
            t.column("createdAt", .integer).notNull()
            t.column("modifiedAt", .integer).notNull()
            t.column("deletedAt", .integer)
        }
        try db.create(table: "vehicle_pid_settings") { t in
            t.column("vehicleID", .text).notNull().references("vehicles", onDelete: .cascade)
            t.column("service", .integer).notNull()
            t.column("pid", .integer).notNull()
            t.column("isSupported", .boolean).notNull()
            t.column("isCollectionEnabled", .boolean).notNull()
            t.column("discoveredAt", .integer).notNull()
            t.primaryKey(["vehicleID", "service", "pid"])
        }
    }

    /// 責務: 整備記録のテーブルを作成します。
    private static func createMaintenanceTables(_ db: Database) throws {
        try db.create(table: "maintenance_records") { t in
            t.primaryKey("id", .text)
            t.column("vehicleID", .text).notNull().references("vehicles", onDelete: .cascade)
            t.column("kind", .text).notNull()
            t.column("title", .text).notNull()
            t.column("performedAt", .integer).notNull()
            t.column("odometerKilometers", .double)
            t.column("notes", .text).notNull()
            t.column("detail", .blob).notNull() // workItems / photos / fastenerGroups のJSON
            t.column("createdAt", .integer).notNull()
            t.column("modifiedAt", .integer).notNull()
            t.column("deletedAt", .integer)
        }
        try db.create(index: "maintenance_records_vehicle_performed", on: "maintenance_records", columns: ["vehicleID", "performedAt"])
    }

    /// 責務: 走行セッション・取得条件・Rawサンプルのテーブルと追記専用トリガーを作成します。
    private static func createSessionTables(_ db: Database) throws {
        try db.create(table: "sessions") { t in
            t.primaryKey("id", .text)
            t.column("vehicleID", .text).notNull().references("vehicles", onDelete: .cascade)
            t.column("startedAt", .integer).notNull()
            t.column("endedAt", .integer)
            t.column("endReason", .text)
            t.column("isDemo", .boolean).notNull()
            t.column("adapterName", .text).notNull()
            t.column("adapterTransport", .text).notNull()
            t.column("platform", .text).notNull()
            t.column("deviceID", .text).notNull()
            t.column("deviceName", .text).notNull()
            t.column("appVersion", .text).notNull()
            t.column("appBuild", .text).notNull()
            t.column("pollingPolicyVersion", .integer).notNull()
            t.column("odometerStartKilometers", .double)
            t.column("odometerEndKilometers", .double)
            t.column("distanceSource", .text)
            t.column("sampleCount", .integer).notNull().defaults(to: 0)
            t.column("respondedCount", .integer).notNull().defaults(to: 0)
            t.column("payloadByteCount", .integer).notNull().defaults(to: 0)
            t.column("rawAvailability", .text).notNull()
            t.column("archiveDigest", .text)
            t.column("modifiedAt", .integer).notNull()
            t.column("deletedAt", .integer)
            t.check(sql: "(endedAt IS NULL) = (endReason IS NULL)")
        }
        try db.create(index: "sessions_vehicle_started", on: "sessions", columns: ["vehicleID", "startedAt"])

        try db.create(table: "session_pids") { t in
            t.column("sessionID", .text).notNull().references("sessions", onDelete: .cascade)
            t.column("ordinal", .integer).notNull()
            t.column("service", .integer).notNull()
            t.column("pid", .integer).notNull()
            t.column("header", .integer)
            t.column("support", .text).notNull()
            t.column("isCollectionEnabled", .boolean).notNull()
            t.column("isFastGroup", .boolean).notNull()
            t.column("definitionRevision", .integer).notNull()
            t.column("requiredByteCount", .integer)
            t.column("formula", .text)
            t.column("unit", .text).notNull()
            t.column("minimumValue", .double)
            t.column("maximumValue", .double)
            t.primaryKey(["sessionID", "ordinal"])
            t.uniqueKey(["sessionID", "service", "pid"])
        }

        try db.create(table: "session_samples", options: .withoutRowID) { t in
            t.column("sessionID", .text).notNull().references("sessions", onDelete: .cascade)
            t.column("sequence", .integer).notNull()
            t.column("tick", .integer).notNull()
            t.column("elapsedMicroseconds", .integer).notNull()
            t.column("service", .integer).notNull()
            t.column("pid", .integer).notNull()
            t.column("outcome", .integer).notNull() // SampleOutcome.rawValue
            t.column("payload", .blob).notNull()
            t.primaryKey(["sessionID", "sequence"])
        }

        for table in ["session_pids", "session_samples"] {
            try db.execute(sql: """
                CREATE TRIGGER \(table)_append_only BEFORE UPDATE ON \(table)
                BEGIN SELECT RAISE(ABORT, '\(table) is append-only'); END
                """)
        }
    }

    /// 責務: CloudKit同期の管理用テーブルを作成します。
    private static func createSyncTables(_ db: Database) throws {
        // レコードごとのCloudKitシステムフィールドと、最後に同期した時点の modifiedAt。
        try db.create(table: "sync_records") { t in
            t.column("recordType", .text).notNull()
            t.column("recordID", .text).notNull()
            t.column("systemFields", .blob)
            t.column("syncedModifiedAt", .integer)
            t.primaryKey(["recordType", "recordID"])
        }
        // 同期エンジンの状態(変更トークンなど)。
        try db.create(table: "sync_state") { t in
            t.primaryKey("key", .text)
            t.column("value", .blob).notNull()
        }
    }
}
