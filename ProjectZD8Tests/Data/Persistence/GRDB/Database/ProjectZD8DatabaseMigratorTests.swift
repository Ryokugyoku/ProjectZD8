import Foundation
import CryptoKit
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

    /// 製品版baselineと取得証拠のforward-only Migration識別子を登録します。
    ///
    /// 責務: 既存baselineを変更せず取得証拠migrationが後続登録されることを確認します。
    func testMigratorPreservesBaselineAndAddsAcquisitionEvidenceMigration() {
        XCTAssertEqual(
            ProjectZD8DatabaseMigrator.migrator.migrations,
            [
                "release_v1_create_schema",
                "release_v1_add_connection_session_acquisition_evidence",
                "release_v1_add_connection_session_acquisition_batch_evidence"
            ]
        )
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
            try database.drop(table: ConnectionSessionAcquisitionPIDRequestRecord.databaseTableName)
            try database.drop(table: ConnectionSessionAcquisitionBatchRecord.databaseTableName)
            try database.drop(table: ConnectionSessionAcquisitionOrderedPIDRecord.databaseTableName)
            try database.drop(table: ConnectionSessionAcquisitionPIDDefinitionRecord.databaseTableName)
            try database.drop(table: ConnectionSessionAcquisitionRawBoundaryRecord.databaseTableName)
            try database.drop(table: ConnectionSessionAcquisitionManifestRecord.databaseTableName)
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
                [
                    "release_v1_add_connection_session_acquisition_batch_evidence",
                    "release_v1_add_connection_session_acquisition_evidence",
                    "release_v1_create_schema",
                    "v8_add_connection_session_raw_last_accessed_at"
                ]
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

    /// 空DBへ全migrationを適用して取得証拠表、外部キー、index、trigger、整合性を確認します。
    ///
    /// 責務: 新規DBがlegacy evidenceを生成せず取得証拠schemaを完全作成することを確認します。
    func testFreshDatabaseCreatesAcquisitionEvidenceSchemaWithoutRows() throws {
        let queue = try DatabaseQueue()

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        try queue.read { database in
            for table in acquisitionTables {
                XCTAssertTrue(try database.tableExists(table))
                XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table)"), 0)
            }
            XCTAssertEqual(
                try String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'acquisition_%' ORDER BY name"
                ).count,
                11
            )
            XCTAssertEqual(
                try String.fetchAll(
                    database,
                    sql: """
                        SELECT name FROM sqlite_master
                        WHERE type = 'index'
                            AND tbl_name LIKE 'connection_session_acquisition_%'
                            AND name NOT LIKE 'sqlite_autoindex_%'
                        ORDER BY name
                        """
                ),
                [
                    "acquisition_batches_session_completion",
                    "acquisition_pid_requests_pid_outcome"
                ]
            )
            XCTAssertTrue(try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty)
            XCTAssertEqual(try String.fetchOne(database, sql: "PRAGMA integrity_check"), "ok")
            let manifestForeignKeys = try Row.fetchAll(
                database,
                sql: "PRAGMA foreign_key_list(connection_session_acquisition_manifests)"
            )
            XCTAssertEqual(manifestForeignKeys.count, 1)
            XCTAssertEqual(manifestForeignKeys[0]["table"] as String, "connection_sessions")
            XCTAssertEqual(manifestForeignKeys[0]["on_delete"] as String, "CASCADE")
            let orderedForeignKeys = try Row.fetchAll(
                database,
                sql: "PRAGMA foreign_key_list(connection_session_acquisition_ordered_pids)"
            )
            XCTAssertEqual(orderedForeignKeys.count, 3)
        }
    }

    /// release_v1 baseline DBへ新migrationだけを適用してsessionとRawを不変保持します。
    ///
    /// 責務: 現行release baseline fixtureの全session/Raw値とtest側digestがadditive migration前後で一致することを確認します。
    func testReleaseBaselineMigrationPreservesSessionsAndRawRows() throws {
        let queue = try DatabaseQueue()
        let migrator = ProjectZD8DatabaseMigrator.migrator
        try migrator.migrate(queue, upTo: "release_v1_create_schema")
        try insertSyntheticSessionAndRaw(in: queue, migrationIdentifiers: [])
        let before = try migrationSnapshot(in: queue)

        try migrator.migrate(queue)

        let after = try migrationSnapshot(in: queue)
        XCTAssertEqual(after, before)
        try assertDatabaseIntegrity(queue)
        try queue.read { database in
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_acquisition_manifests"), 0)
        }
    }

    /// git履歴の旧v8 DDL相当DBへforward-only migrationを適用します。
    ///
    /// 責務: commit `7a6ce2d` の `ConnectionSessionDatabaseMigrator.swift` にあるv2〜v8定義を再現したsynthetic fixtureのsession/Raw不変性を確認します。
    func testLegacyV8FixtureMigrationPreservesSessionsAndRawRows() throws {
        let queue = try DatabaseQueue()
        try createLegacyV8Fixture(in: queue)
        try insertSyntheticSessionAndRaw(
            in: queue,
            migrationIdentifiers: [
                "v2_create_connection_sessions",
                "v3_add_connection_session_odometer_bounds",
                "v4_add_raw_log_transfer_state",
                "v5_add_connection_session_stop_review",
                "v6_add_distance_source_model_code",
                "v7_add_connection_session_acquisition_device",
                "v8_add_connection_session_raw_last_accessed_at"
            ]
        )
        let before = try migrationSnapshot(in: queue)

        try ProjectZD8DatabaseMigrator.migrator.migrate(queue)

        XCTAssertEqual(try migrationSnapshot(in: queue), before)
        try assertDatabaseIntegrity(queue)
        try queue.read { database in
            XCTAssertEqual(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM connection_session_acquisition_manifests"), 0)
            XCTAssertTrue(try database.tableExists(MaintenanceRecordRecord.databaseTableName))
        }
    }

    /// migration fixtureへsessionと順序付きRaw行を投入します。
    ///
    /// 責務: migration不変性検証用の全Raw列と親manifestDigestを持つsyntheticデータを保存します。
    /// - Parameters:
    ///   - queue: 投入先DB Queue。
    ///   - migrationIdentifiers: 旧fixtureで記録するmigration履歴。
    /// - Throws: SQLite書込失敗。
    private func insertSyntheticSessionAndRaw(
        in queue: DatabaseQueue,
        migrationIdentifiers: [String]
    ) throws {
        try queue.write { database in
            for identifier in migrationIdentifiers {
                try database.execute(
                    sql: "INSERT OR IGNORE INTO grdb_migrations(identifier) VALUES (?)",
                    arguments: [identifier]
                )
            }
            try database.execute(
                sql: """
                    INSERT INTO connection_sessions (
                        id, accountIdentifier, startedAt, endedAt, endReason,
                        rawRecordCount, rawByteCount, localRawState, cloudSyncState, manifestDigest
                    ) VALUES ('fixture-session', 'fixture-account', ?, ?, 'userDisconnected', 2, 3, 'available', 'uploaded', 'fixture-manifest-digest')
                    """,
                arguments: [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)]
            )
            try database.execute(
                sql: """
                    INSERT INTO connection_session_raw_logs
                        (sessionID, sequence, observedAt, batchElapsedNanoseconds, service, pid, payload)
                    VALUES
                        ('fixture-session', 0, ?, 101, 1, 12, X'01FF'),
                        ('fixture-session', 1, ?, 202, 1, 5, X'80')
                    """,
                arguments: [Date(timeIntervalSince1970: 101), Date(timeIntervalSince1970: 102)]
            )
        }
    }

    /// 旧TestFlight相当のv2〜v8 connection-session schemaを作成します。
    ///
    /// 責務: commit `7a6ce2d` の旧DDLを実ユーザーデータなしでSQLite fixtureへ再現します。
    /// - Parameter queue: schema作成先DB Queue。
    /// - Throws: SQLite DDL失敗。
    private func createLegacyV8Fixture(in queue: DatabaseQueue) throws {
        try queue.write { database in
            try database.execute(sql: """
                CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
                CREATE TABLE connection_sessions (
                    id TEXT PRIMARY KEY NOT NULL CHECK (length(id) > 0),
                    accountIdentifier TEXT NOT NULL CHECK (length(accountIdentifier) > 0),
                    startedAt DATETIME NOT NULL,
                    endedAt DATETIME,
                    endReason TEXT,
                    vehicleID TEXT,
                    vehicleName TEXT,
                    vehicleDisplayIdentifier TEXT,
                    startingOdometerKilometers DOUBLE,
                    endingOdometerKilometers DOUBLE,
                    rawRecordCount INTEGER NOT NULL DEFAULT 0,
                    rawByteCount INTEGER NOT NULL DEFAULT 0,
                    localRawState TEXT NOT NULL DEFAULT 'empty',
                    cloudSyncState TEXT NOT NULL DEFAULT 'notUploaded',
                    manifestDigest TEXT,
                    macImportedDeviceID TEXT,
                    macImportedDeviceName TEXT,
                    macImportedAt DATETIME,
                    macImportedManifestDigest TEXT,
                    stopReviewDecision TEXT,
                    distanceSourceModelCode TEXT,
                    acquisitionPlatform TEXT,
                    acquisitionDeviceName TEXT,
                    rawLastAccessedAt DATETIME,
                    CHECK ((endedAt IS NULL AND endReason IS NULL) OR (endedAt IS NOT NULL AND endReason IS NOT NULL)),
                    CHECK ((vehicleID IS NULL AND vehicleName IS NULL AND vehicleDisplayIdentifier IS NULL)
                        OR (vehicleID IS NOT NULL AND vehicleName IS NOT NULL AND vehicleDisplayIdentifier IS NOT NULL))
                );
                CREATE INDEX connection_sessions_account_started_at
                    ON connection_sessions(accountIdentifier, startedAt);
                CREATE INDEX connection_sessions_vehicle_started_at
                    ON connection_sessions(accountIdentifier, vehicleID, startedAt);
                CREATE TABLE connection_session_raw_logs (
                    sessionID TEXT NOT NULL REFERENCES connection_sessions(id) ON DELETE CASCADE,
                    sequence INTEGER NOT NULL CHECK (sequence >= 0),
                    observedAt DATETIME NOT NULL,
                    batchElapsedNanoseconds INTEGER NOT NULL CHECK (batchElapsedNanoseconds >= 0),
                    service INTEGER NOT NULL CHECK (service BETWEEN 0 AND 255),
                    pid INTEGER NOT NULL CHECK (pid BETWEEN 0 AND 255),
                    payload BLOB NOT NULL,
                    PRIMARY KEY (sessionID, sequence)
                );
                CREATE INDEX connection_session_raw_logs_session_observed_at
                    ON connection_session_raw_logs(sessionID, observedAt);
                """)
        }
    }

    /// sessionとRaw全列からmigration前後比較snapshotを生成します。
    ///
    /// 責務: session集合、Raw順序/件数/bytes/時刻/Service/PID、親digest、canonical Raw digestを固定します。
    /// - Parameter queue: 読取対象DB Queue。
    /// - Returns: migration前後で完全比較するsnapshot。
    /// - Throws: SQLite読取失敗。
    private func migrationSnapshot(in queue: DatabaseQueue) throws -> MigrationSnapshot {
        try queue.read { database in
            let sessionIDs = try String.fetchAll(database, sql: "SELECT id FROM connection_sessions ORDER BY id")
            let rows = try Row.fetchAll(
                database,
                sql: """
                    SELECT sessionID, sequence, observedAt, batchElapsedNanoseconds, service, pid, payload
                    FROM connection_session_raw_logs ORDER BY sessionID, sequence
                    """
            )
            var canonical = Data()
            var perSessionCounts: [String: Int] = [:]
            var rawRows: [MigrationRawRow] = []
            for row in rows {
                let sessionID: String = row["sessionID"]
                let sequence: Int64 = row["sequence"]
                let observedAt: Date = row["observedAt"]
                let elapsed: Int64 = row["batchElapsedNanoseconds"]
                let service: Int = row["service"]
                let pid: Int = row["pid"]
                let payload: Data = row["payload"]
                perSessionCounts[sessionID, default: 0] += 1
                rawRows.append(MigrationRawRow(
                    sessionID: sessionID,
                    sequence: sequence,
                    observedAt: observedAt,
                    batchElapsedNanoseconds: elapsed,
                    service: service,
                    pid: pid,
                    payload: payload
                ))
                canonical.append(Data("\(sessionID)|\(sequence)|\(observedAt.timeIntervalSince1970)|\(elapsed)|\(service)|\(pid)|".utf8))
                canonical.append(payload)
            }
            return MigrationSnapshot(
                sessionCount: sessionIDs.count,
                sessionIDs: sessionIDs,
                rawCount: rows.count,
                rawCountsBySession: perSessionCounts,
                rawRows: rawRows,
                rawCanonicalDigest: Data(SHA256.hash(data: canonical)),
                parentManifestDigests: try String.fetchAll(
                    database,
                    sql: "SELECT COALESCE(manifestDigest, '') FROM connection_sessions ORDER BY id"
                )
            )
        }
    }

    /// SQLiteのFKと全体整合性を確認します。
    ///
    /// 責務: migration後DBに外部キー違反とintegrity failureがないことを検証します。
    /// - Parameter queue: 検証対象DB Queue。
    /// - Throws: SQLite検査失敗。
    private func assertDatabaseIntegrity(_ queue: DatabaseQueue) throws {
        try queue.read { database in
            XCTAssertTrue(try Row.fetchAll(database, sql: "PRAGMA foreign_key_check").isEmpty)
            XCTAssertEqual(try String.fetchOne(database, sql: "PRAGMA integrity_check"), "ok")
        }
    }

    /// 取得証拠の正規化6表名です。
    private var acquisitionTables: [String] {
        [
            "connection_session_acquisition_manifests",
            "connection_session_acquisition_pid_definitions",
            "connection_session_acquisition_ordered_pids",
            "connection_session_acquisition_raw_boundaries",
            "connection_session_acquisition_batches",
            "connection_session_acquisition_pid_requests"
        ]
    }
}

/// migration前後で比較するsessionとRawのcanonical snapshotです。
private struct MigrationSnapshot: Equatable {
    /// session総数です。
    let sessionCount: Int
    /// session ID集合を安定順で保持します。
    let sessionIDs: [String]
    /// Raw総数です。
    let rawCount: Int
    /// session別Raw件数です。
    let rawCountsBySession: [String: Int]
    /// sessionIDとsequence順のRaw全semantic列です。
    let rawRows: [MigrationRawRow]
    /// sequence順の全Raw semantic列から作るtest側SHA-256です。
    let rawCanonicalDigest: Data
    /// 親sessionの既存manifestDigestです。
    let parentManifestDigests: [String]
}

/// migration不変性を列単位で比較する1件のsynthetic Raw行です。
private struct MigrationRawRow: Equatable {
    /// 親session IDです。
    let sessionID: String
    /// session内のRaw順序です。
    let sequence: Int64
    /// Raw観測時刻です。
    let observedAt: Date
    /// batch開始からの単調経過nanosecondです。
    let batchElapsedNanoseconds: Int64
    /// OBD Service番号です。
    let service: Int
    /// Service内PID番号です。
    let pid: Int
    /// 未decode payload bytesです。
    let payload: Data
}
