import GRDB

/// 製品DBの現行SQLiteスキーマと旧開発DBの非破壊移行を定義します。
enum ProjectZD8DatabaseMigrator {
    /// 製品版baselineと後続のadditive schemaを順に適用するforward-only migratorです。
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
        migrator.registerMigration("release_v1_add_connection_session_acquisition_evidence") { database in
            try createConnectionSessionAcquisitionEvidence(in: database)
        }
        migrator.registerMigration("release_v1_add_connection_session_acquisition_batch_evidence") { database in
            try createConnectionSessionAcquisitionBatchEvidence(in: database)
        }
        return migrator
    }

    /// 取得batchとPID request evidenceの正規化表を追加します。
    ///
    /// 責務: 既存Raw表を変更せずpartial取得を復元できるbatch/request表と不変性制約を追加します。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: テーブル、index、triggerの作成に失敗した場合のGRDBエラー。
    nonisolated private static func createConnectionSessionAcquisitionBatchEvidence(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE connection_session_acquisition_batches (
                sessionID TEXT NOT NULL
                    REFERENCES connection_session_acquisition_manifests(sessionID) ON DELETE CASCADE,
                batchOrdinal INTEGER NOT NULL CHECK (batchOrdinal >= 0),
                generation INTEGER NOT NULL CHECK (generation >= 0),
                policyTick INTEGER NOT NULL CHECK (policyTick >= 0),
                selectionEvaluationComplete INTEGER NOT NULL CHECK (selectionEvaluationComplete IN (0, 1)),
                startedAtMicroseconds INTEGER NOT NULL,
                completionState TEXT CHECK (completionState IN ('completed', 'failed', 'terminatedUnknown')),
                completedAtMicroseconds INTEGER,
                failureCode TEXT CHECK (failureCode IN (
                    'transportUnavailable', 'cancelled', 'persistenceFailure',
                    'backpressureStopped', 'processTerminated', 'unclassifiedResult'
                )),
                isSealed INTEGER NOT NULL CHECK (isSealed IN (0, 1)),
                PRIMARY KEY (sessionID, batchOrdinal),
                CHECK (
                    (completionState IS NULL AND completedAtMicroseconds IS NULL AND failureCode IS NULL AND isSealed = 0)
                    OR
                    (completionState = 'completed' AND completedAtMicroseconds IS NOT NULL
                        AND completedAtMicroseconds >= startedAtMicroseconds
                        AND failureCode IS NULL AND selectionEvaluationComplete = 1 AND isSealed = 1)
                    OR
                    (completionState IN ('failed', 'terminatedUnknown') AND completedAtMicroseconds IS NOT NULL
                        AND completedAtMicroseconds >= startedAtMicroseconds
                        AND failureCode IS NOT NULL AND isSealed = 1)
                )
            );

            CREATE TABLE connection_session_acquisition_pid_requests (
                sessionID TEXT NOT NULL,
                batchOrdinal INTEGER NOT NULL,
                requestOrdinal INTEGER NOT NULL CHECK (requestOrdinal >= 0),
                manifestPIDOrdinal INTEGER NOT NULL CHECK (manifestPIDOrdinal >= 0),
                dispatchState TEXT NOT NULL CHECK (dispatchState IN ('selectedOnly', 'dispatchBegun', 'terminal')),
                transportOutcome TEXT CHECK (transportOutcome IN (
                    'responded', 'unsupported', 'timedOut', 'cancelled', 'transportFailure',
                    'unknownAfterTermination', 'unclassifiedResponse'
                )),
                valueOutcome TEXT NOT NULL CHECK (valueOutcome IN (
                    'notEvaluated', 'decodedValid', 'decodeFailure', 'invalidValue'
                )),
                rawSequence INTEGER,
                elapsedNanoseconds INTEGER CHECK (elapsedNanoseconds >= 0),
                reasonCode TEXT CHECK (reasonCode IS NULL OR length(reasonCode) > 0),
                isSealed INTEGER NOT NULL CHECK (isSealed IN (0, 1)),
                PRIMARY KEY (sessionID, batchOrdinal, requestOrdinal),
                UNIQUE (sessionID, batchOrdinal, manifestPIDOrdinal),
                UNIQUE (sessionID, rawSequence),
                FOREIGN KEY (sessionID, batchOrdinal)
                    REFERENCES connection_session_acquisition_batches(sessionID, batchOrdinal) ON DELETE CASCADE,
                FOREIGN KEY (sessionID, manifestPIDOrdinal)
                    REFERENCES connection_session_acquisition_ordered_pids(sessionID, ordinal),
                FOREIGN KEY (sessionID, rawSequence)
                    REFERENCES connection_session_raw_logs(sessionID, sequence),
                CHECK (
                    (dispatchState IN ('selectedOnly', 'dispatchBegun')
                        AND transportOutcome IS NULL AND valueOutcome = 'notEvaluated'
                        AND rawSequence IS NULL AND elapsedNanoseconds IS NULL AND isSealed = 0)
                    OR
                    (dispatchState = 'terminal' AND transportOutcome IS NOT NULL AND isSealed = 1
                        AND (
                            (transportOutcome = 'responded' AND rawSequence IS NOT NULL)
                            OR
                            (transportOutcome != 'responded' AND rawSequence IS NULL AND valueOutcome = 'notEvaluated')
                        ))
                )
            );

            CREATE INDEX acquisition_batches_session_completion
                ON connection_session_acquisition_batches(sessionID, completionState, batchOrdinal);
            CREATE INDEX acquisition_pid_requests_pid_outcome
                ON connection_session_acquisition_pid_requests(sessionID, manifestPIDOrdinal, transportOutcome);

            CREATE TRIGGER acquisition_batch_update_guard
            BEFORE UPDATE ON connection_session_acquisition_batches
            WHEN OLD.isSealed != 0 OR NOT (
                OLD.sessionID = NEW.sessionID
                AND OLD.batchOrdinal = NEW.batchOrdinal
                AND OLD.generation = NEW.generation
                AND OLD.policyTick = NEW.policyTick
                AND OLD.selectionEvaluationComplete = NEW.selectionEvaluationComplete
                AND OLD.startedAtMicroseconds = NEW.startedAtMicroseconds
                AND OLD.completionState IS NULL
                AND NEW.completionState IS NOT NULL
                AND NEW.isSealed = 1
            )
            BEGIN
                SELECT RAISE(ABORT, 'acquisition batch is append-only');
            END;

            CREATE TRIGGER acquisition_request_update_guard
            BEFORE UPDATE ON connection_session_acquisition_pid_requests
            WHEN OLD.isSealed != 0 OR NOT (
                OLD.sessionID = NEW.sessionID
                AND OLD.batchOrdinal = NEW.batchOrdinal
                AND OLD.requestOrdinal = NEW.requestOrdinal
                AND OLD.manifestPIDOrdinal = NEW.manifestPIDOrdinal
                AND (
                    (OLD.dispatchState = 'selectedOnly' AND NEW.dispatchState = 'dispatchBegun' AND NEW.isSealed = 0)
                    OR
                    (OLD.dispatchState IN ('selectedOnly', 'dispatchBegun')
                        AND NEW.dispatchState = 'terminal' AND NEW.isSealed = 1)
                )
            )
            BEGIN
                SELECT RAISE(ABORT, 'acquisition request is append-only');
            END;

            CREATE TRIGGER acquisition_completed_batch_guard
            BEFORE UPDATE ON connection_session_acquisition_batches
            WHEN NEW.completionState = 'completed' AND (
                EXISTS (
                    SELECT 1 FROM connection_session_acquisition_pid_requests
                    WHERE sessionID = NEW.sessionID AND batchOrdinal = NEW.batchOrdinal
                        AND dispatchState != 'terminal'
                )
                OR (
                    EXISTS (
                        SELECT 1 FROM connection_session_acquisition_pid_requests
                        WHERE sessionID = NEW.sessionID AND batchOrdinal = NEW.batchOrdinal
                    )
                    AND (
                        (SELECT MIN(requestOrdinal) FROM connection_session_acquisition_pid_requests
                            WHERE sessionID = NEW.sessionID AND batchOrdinal = NEW.batchOrdinal) != 0
                        OR
                        (SELECT MAX(requestOrdinal) FROM connection_session_acquisition_pid_requests
                            WHERE sessionID = NEW.sessionID AND batchOrdinal = NEW.batchOrdinal)
                            != (SELECT COUNT(*) - 1 FROM connection_session_acquisition_pid_requests
                                WHERE sessionID = NEW.sessionID AND batchOrdinal = NEW.batchOrdinal)
                    )
                )
            )
            BEGIN
                SELECT RAISE(ABORT, 'completed acquisition batch requires contiguous terminal requests');
            END;
            """)
    }

    /// 取得manifest、PID snapshot、要求順、Raw境界の正規化表を追加します。
    ///
    /// 責務: 既存セッションとRaw行を変更せず取得証拠用の4表と不変性triggerを追加します。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: テーブルまたはtriggerの作成に失敗した場合のGRDBエラー。
    nonisolated private static func createConnectionSessionAcquisitionEvidence(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE connection_session_acquisition_manifests (
                sessionID TEXT PRIMARY KEY NOT NULL
                    REFERENCES connection_sessions(id) ON DELETE CASCADE,
                manifestVersion INTEGER NOT NULL CHECK (manifestVersion > 0),
                applicationMarketingVersion TEXT NOT NULL CHECK (length(applicationMarketingVersion) > 0),
                applicationBuildVersion TEXT NOT NULL CHECK (length(applicationBuildVersion) > 0),
                schemaContractVersion INTEGER NOT NULL CHECK (schemaContractVersion > 0),
                pollingPolicyVersion INTEGER NOT NULL CHECK (pollingPolicyVersion > 0),
                acquisitionPlatform TEXT NOT NULL CHECK (acquisitionPlatform IN ('iPhone', 'iPad', 'macOS')),
                modelInputManifestVersion INTEGER NOT NULL CHECK (modelInputManifestVersion > 0),
                isSealed INTEGER NOT NULL CHECK (isSealed IN (0, 1))
            );

            CREATE TABLE connection_session_acquisition_pid_definitions (
                sessionID TEXT NOT NULL
                    REFERENCES connection_session_acquisition_manifests(sessionID) ON DELETE CASCADE,
                service INTEGER NOT NULL CHECK (service BETWEEN 0 AND 255),
                pid INTEGER NOT NULL CHECK (pid BETWEEN 0 AND 255),
                capabilitySupport TEXT NOT NULL CHECK (capabilitySupport IN ('supported', 'unsupported', 'indeterminate')),
                isCollectionEnabled INTEGER NOT NULL CHECK (isCollectionEnabled IN (0, 1)),
                definitionRevision INTEGER NOT NULL CHECK (definitionRevision > 0),
                requiredByteCount INTEGER NOT NULL CHECK (requiredByteCount > 0),
                formulaCanonicalizationVersion INTEGER NOT NULL CHECK (formulaCanonicalizationVersion > 0),
                formulaExpression TEXT NOT NULL CHECK (length(formulaExpression) > 0),
                unit TEXT NOT NULL CHECK (length(unit) > 0),
                validityRangeKind TEXT NOT NULL CHECK (validityRangeKind IN ('notDeclared', 'inclusive')),
                minimumValue REAL,
                maximumValue REAL,
                PRIMARY KEY (sessionID, service, pid),
                CHECK (
                    (validityRangeKind = 'notDeclared' AND minimumValue IS NULL AND maximumValue IS NULL)
                    OR
                    (validityRangeKind = 'inclusive'
                        AND minimumValue IS NOT NULL AND maximumValue IS NOT NULL
                        AND typeof(minimumValue) IN ('real', 'integer')
                        AND typeof(maximumValue) IN ('real', 'integer')
                        AND minimumValue BETWEEN -1.7976931348623157e308 AND 1.7976931348623157e308
                        AND maximumValue BETWEEN -1.7976931348623157e308 AND 1.7976931348623157e308
                        AND minimumValue <= maximumValue)
                )
            );

            CREATE TABLE connection_session_acquisition_ordered_pids (
                sessionID TEXT NOT NULL,
                ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
                service INTEGER NOT NULL CHECK (service BETWEEN 0 AND 255),
                pid INTEGER NOT NULL CHECK (pid BETWEEN 0 AND 255),
                PRIMARY KEY (sessionID, ordinal),
                UNIQUE (sessionID, service, pid),
                FOREIGN KEY (sessionID, service, pid)
                    REFERENCES connection_session_acquisition_pid_definitions(sessionID, service, pid)
                    ON DELETE CASCADE
            );

            CREATE TABLE connection_session_acquisition_raw_boundaries (
                sessionID TEXT NOT NULL
                    REFERENCES connection_session_acquisition_manifests(sessionID) ON DELETE CASCADE,
                eventKind TEXT NOT NULL CHECK (eventKind IN ('started', 'ended')),
                occurredAtMicroseconds INTEGER NOT NULL,
                endReason TEXT,
                PRIMARY KEY (sessionID, eventKind),
                CHECK (
                    (eventKind = 'started' AND endReason IS NULL)
                    OR
                    (eventKind = 'ended' AND endReason IN (
                        'userDisconnected', 'vehicleNoResponse', 'connectionLost', 'acquisitionFailed',
                        'superseded', 'accountSignedOut', 'unexpectedTermination'
                    ))
                )
            );

            CREATE TRIGGER acquisition_manifest_update_guard
            BEFORE UPDATE ON connection_session_acquisition_manifests
            WHEN NOT (
                OLD.isSealed = 0 AND NEW.isSealed = 1
                AND OLD.sessionID = NEW.sessionID
                AND OLD.manifestVersion = NEW.manifestVersion
                AND OLD.applicationMarketingVersion = NEW.applicationMarketingVersion
                AND OLD.applicationBuildVersion = NEW.applicationBuildVersion
                AND OLD.schemaContractVersion = NEW.schemaContractVersion
                AND OLD.pollingPolicyVersion = NEW.pollingPolicyVersion
                AND OLD.acquisitionPlatform = NEW.acquisitionPlatform
                AND OLD.modelInputManifestVersion = NEW.modelInputManifestVersion
                AND EXISTS (
                    SELECT 1 FROM connection_session_acquisition_raw_boundaries
                    WHERE sessionID = OLD.sessionID AND eventKind = 'started'
                )
                AND (
                    NOT EXISTS (
                        SELECT 1 FROM connection_session_acquisition_ordered_pids
                        WHERE sessionID = OLD.sessionID
                    )
                    OR (
                        (SELECT MIN(ordinal) FROM connection_session_acquisition_ordered_pids WHERE sessionID = OLD.sessionID) = 0
                        AND (SELECT MAX(ordinal) FROM connection_session_acquisition_ordered_pids WHERE sessionID = OLD.sessionID)
                            = (SELECT COUNT(*) - 1 FROM connection_session_acquisition_ordered_pids WHERE sessionID = OLD.sessionID)
                    )
                )
            )
            BEGIN
                SELECT RAISE(ABORT, 'acquisition manifest is immutable');
            END;

            CREATE TRIGGER acquisition_pid_definition_insert_guard
            BEFORE INSERT ON connection_session_acquisition_pid_definitions
            WHEN COALESCE((SELECT isSealed FROM connection_session_acquisition_manifests WHERE sessionID = NEW.sessionID), 1) != 0
            BEGIN
                SELECT RAISE(ABORT, 'sealed acquisition manifest rejects PID definition insert');
            END;

            CREATE TRIGGER acquisition_pid_definition_update_guard
            BEFORE UPDATE ON connection_session_acquisition_pid_definitions
            BEGIN
                SELECT RAISE(ABORT, 'acquisition PID definition is immutable');
            END;

            CREATE TRIGGER acquisition_ordered_pid_insert_guard
            BEFORE INSERT ON connection_session_acquisition_ordered_pids
            WHEN COALESCE((SELECT isSealed FROM connection_session_acquisition_manifests WHERE sessionID = NEW.sessionID), 1) != 0
            BEGIN
                SELECT RAISE(ABORT, 'sealed acquisition manifest rejects ordered PID insert');
            END;

            CREATE TRIGGER acquisition_ordered_pid_update_guard
            BEFORE UPDATE ON connection_session_acquisition_ordered_pids
            BEGIN
                SELECT RAISE(ABORT, 'acquisition ordered PID is immutable');
            END;

            CREATE TRIGGER acquisition_raw_boundary_update_guard
            BEFORE UPDATE ON connection_session_acquisition_raw_boundaries
            BEGIN
                SELECT RAISE(ABORT, 'acquisition Raw boundary is immutable');
            END;

            CREATE TRIGGER acquisition_started_insert_guard
            BEFORE INSERT ON connection_session_acquisition_raw_boundaries
            WHEN NEW.eventKind = 'started'
                AND COALESCE((SELECT isSealed FROM connection_session_acquisition_manifests WHERE sessionID = NEW.sessionID), 1) != 0
            BEGIN
                SELECT RAISE(ABORT, 'sealed acquisition manifest rejects started boundary');
            END;

            CREATE TRIGGER acquisition_ended_insert_guard
            BEFORE INSERT ON connection_session_acquisition_raw_boundaries
            WHEN NEW.eventKind = 'ended' AND (
                NOT EXISTS (
                    SELECT 1 FROM connection_session_acquisition_raw_boundaries
                    WHERE sessionID = NEW.sessionID AND eventKind = 'started'
                )
                OR NEW.occurredAtMicroseconds < (
                    SELECT occurredAtMicroseconds FROM connection_session_acquisition_raw_boundaries
                    WHERE sessionID = NEW.sessionID AND eventKind = 'started'
                )
            )
            BEGIN
                SELECT RAISE(ABORT, 'ended boundary requires an earlier started boundary');
            END;
            """)
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
