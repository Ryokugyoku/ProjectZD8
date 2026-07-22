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
        migrator.registerMigration("v3_add_connection_session_odometer_bounds") { database in
            try database.alter(table: ConnectionSessionRecord.databaseTableName) { table in
                table.add(column: "startingOdometerKilometers", .double)
                table.add(column: "endingOdometerKilometers", .double)
            }
        }
        migrator.registerMigration("v4_add_raw_log_transfer_state") { database in
            try database.alter(table: ConnectionSessionRecord.databaseTableName) { table in
                table.add(column: "rawRecordCount", .integer).notNull().defaults(to: 0)
                table.add(column: "rawByteCount", .integer).notNull().defaults(to: 0)
                table.add(column: "localRawState", .text).notNull().defaults(to: ConnectionSessionLocalRawState.empty.rawValue)
                table.add(column: "cloudSyncState", .text).notNull().defaults(to: ConnectionSessionCloudSyncState.notUploaded.rawValue)
                table.add(column: "manifestDigest", .text)
                table.add(column: "macImportedDeviceID", .text)
                table.add(column: "macImportedDeviceName", .text)
                table.add(column: "macImportedAt", .datetime)
                table.add(column: "macImportedManifestDigest", .text)
            }
            try database.create(table: ConnectionSessionRawLogRecord.databaseTableName) { table in
                table.column("sessionID", .text).notNull()
                    .references(ConnectionSessionRecord.databaseTableName, column: "id", onDelete: .cascade)
                table.column("sequence", .integer).notNull()
                    .check { $0 >= 0 }
                table.column("observedAt", .datetime).notNull()
                table.column("batchElapsedNanoseconds", .integer).notNull()
                    .check { $0 >= 0 }
                table.column("service", .integer).notNull()
                    .check { $0 >= 0 && $0 <= 255 }
                table.column("pid", .integer).notNull()
                    .check { $0 >= 0 && $0 <= 255 }
                table.column("payload", .blob).notNull()
                table.primaryKey(["sessionID", "sequence"])
            }
            try database.create(
                index: "connection_session_raw_logs_session_observed_at",
                on: ConnectionSessionRawLogRecord.databaseTableName,
                columns: ["sessionID", "observedAt"]
            )
            try database.create(
                index: "connection_sessions_vehicle_started_at",
                on: ConnectionSessionRecord.databaseTableName,
                columns: ["accountIdentifier", "vehicleID", "startedAt"]
            )
        }
        migrator.registerMigration("v5_add_connection_session_stop_review") { database in
            try database.alter(table: ConnectionSessionRecord.databaseTableName) { table in
                table.add(column: "stopReviewDecision", .text)
            }
        }
        migrator.registerMigration("v6_add_distance_source_model_code") { database in
            try database.alter(table: ConnectionSessionRecord.databaseTableName) { table in
                table.add(column: "distanceSourceModelCode", .text)
            }
        }
        return migrator
    }
}
