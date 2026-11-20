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
            try ConnectionSessionAcquisitionEvidenceSchema.create(in: database)
        }
        migrator.registerMigration("release_v1_add_connection_session_acquisition_batch_evidence") { database in
            try ConnectionSessionAcquisitionBatchEvidenceSchema.create(in: database)
        }
        migrator.registerMigration("release_v1_add_connection_session_segments_gaps_can_frames") { database in
            try createConnectionSessionSegments(in: database)
            try createConnectionSessionGaps(in: database)
            try createConnectionSessionCANFrames(in: database)
            try addConnectionSessionRawLogSegmentColumns(in: database)
        }
        migrator.registerMigration("release_v1_add_connection_session_observed_vin") { database in
            try addConnectionSessionObservedVIN(in: database)
        }
        migrator.registerMigration("release_v1_add_connection_session_acquisition_adapter_probe") { database in
            try addConnectionSessionAcquisitionAdapterProbeColumns(in: database)
            try recreateAcquisitionManifestUpdateGuard(in: database)
        }
        migrator.registerMigration("release_v1_add_connection_session_location_samples_and_events") { database in
            try ConnectionSessionLocationSchema.create(in: database)
        }
        return migrator
    }

    /// 接続セッション表へ車両未確定時の観測VIN列と索引を追加します。
    ///
    /// 責務: 既存セッション行を変更せず、大文字小文字を区別しない `observedVIN` 列と
    /// アカウント+VIN索引を追加します。
    ///
    /// CHECKは空文字と、先頭・末尾の半角スペース、タブ、LF、CR、垂直タブ、改ページを拒否します。
    /// `ConnectionSession.normalizedObservedVIN` が除くそれ以外のUnicode空白(NBSP、NEL、U+2028、全角スペース等)は
    /// SQLiteで判定できないためCHECKでは拒否せず、Domain側の正規化だけで除きます。
    /// - Parameter database: 列と索引を追加するSQLite接続。
    /// - Throws: 列または索引の追加に失敗した場合のGRDBエラー。
    nonisolated private static func addConnectionSessionObservedVIN(in database: Database) throws {
        try database.execute(sql: """
            ALTER TABLE connection_sessions ADD COLUMN observedVIN TEXT COLLATE NOCASE
                CHECK (observedVIN IS NULL OR (
                    length(observedVIN) > 0
                    AND observedVIN = trim(observedVIN, ' ' || char(9, 10, 11, 12, 13))
                ));
            CREATE INDEX connection_sessions_account_observed_vin
                ON connection_sessions(accountIdentifier, observedVIN);
            """)
    }

    /// 取得manifest表へアダプターのチップ種別とATMA判定結果のNULL可列を追加します。
    ///
    /// 責務: 既存manifest行を変更せず、安定文字列だけを受け付ける2列を追加します。
    /// - Parameter database: 列を追加するSQLite接続。
    /// - Throws: 列追加に失敗した場合のGRDBエラー。
    nonisolated private static func addConnectionSessionAcquisitionAdapterProbeColumns(in database: Database) throws {
        try database.execute(sql: """
            ALTER TABLE connection_session_acquisition_manifests ADD COLUMN adapterChipFamily TEXT
                CHECK (adapterChipFamily IS NULL
                    OR adapterChipFamily IN ('stn', 'elm327Genuine', 'elm327Clone', 'unknown'));
            ALTER TABLE connection_session_acquisition_manifests ADD COLUMN adapterMonitorProbeOutcome TEXT
                CHECK (adapterMonitorProbeOutcome IS NULL
                    OR (adapterChipFamily IS NOT NULL AND adapterMonitorProbeOutcome IN (
                        'framesReceived', 'unsupported', 'bufferFull', 'silent', 'busError', 'stopped'
                    )));
            """)
    }

    /// 取得manifestの不変性triggerを追加列も比較する定義へ置き換えます。
    ///
    /// 責務: seal遷移以外の更新と、seal時のチップ種別・ATMA判定結果の変更を拒否するtriggerを再作成します。
    /// - Parameter database: triggerを再作成するSQLite接続。
    /// - Throws: triggerの削除または作成に失敗した場合のGRDBエラー。
    nonisolated private static func recreateAcquisitionManifestUpdateGuard(in database: Database) throws {
        try database.execute(sql: """
            DROP TRIGGER acquisition_manifest_update_guard;

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
                AND OLD.adapterChipFamily IS NEW.adapterChipFamily
                AND OLD.adapterMonitorProbeOutcome IS NEW.adapterMonitorProbeOutcome
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
            """)
    }

    /// 接続セッション内の連続取得区間を保持する表を追加します。
    ///
    /// 責務: 開始理由、取得モード、終了状態の組み合わせをCHECKで守るセグメント表を1件作成します。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: テーブル作成に失敗した場合のGRDBエラー。
    nonisolated private static func createConnectionSessionSegments(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE connection_session_segments (
                sessionID TEXT NOT NULL
                    REFERENCES connection_sessions(id) ON DELETE CASCADE,
                segmentOrdinal INTEGER NOT NULL CHECK (segmentOrdinal >= 0),
                startReason TEXT NOT NULL CHECK (startReason IN (
                    'initial', 'reconnected', 'processRelaunched', 'modeSwitched'
                )),
                acquisitionMode TEXT NOT NULL CHECK (acquisitionMode IN ('pidPolling', 'canMonitor')),
                startedAtMicroseconds INTEGER NOT NULL,
                monotonicAnchorNanoseconds INTEGER NOT NULL CHECK (monotonicAnchorNanoseconds >= 0),
                firstSequence INTEGER NOT NULL CHECK (firstSequence >= 0),
                endedAtMicroseconds INTEGER,
                endReason TEXT CHECK (endReason IN (
                    'linkLost', 'processTerminated', 'responseStall', 'adapterBufferFull',
                    'bufferOverflow', 'modeSwitched', 'sessionEnded'
                )),
                lastSequence INTEGER CHECK (lastSequence >= firstSequence),
                PRIMARY KEY (sessionID, segmentOrdinal),
                CHECK (
                    (endedAtMicroseconds IS NULL AND endReason IS NULL AND lastSequence IS NULL)
                    OR
                    (endedAtMicroseconds IS NOT NULL AND endReason IS NOT NULL
                        AND endedAtMicroseconds >= startedAtMicroseconds)
                )
            );
            """)
    }

    /// 連続取得区間の間の空白を保持する表を追加します。
    ///
    /// 責務: 前後セグメントへの複合外部キーと欠損原因のCHECKを持つ欠損表を1件作成します。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: テーブル作成に失敗した場合のGRDBエラー。
    nonisolated private static func createConnectionSessionGaps(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE connection_session_gaps (
                sessionID TEXT NOT NULL,
                gapOrdinal INTEGER NOT NULL CHECK (gapOrdinal >= 0),
                precedingSegmentOrdinal INTEGER NOT NULL,
                followingSegmentOrdinal INTEGER,
                startedAtMicroseconds INTEGER NOT NULL,
                endedAtMicroseconds INTEGER CHECK (endedAtMicroseconds >= startedAtMicroseconds),
                cause TEXT NOT NULL CHECK (cause IN (
                    'linkLost', 'processTerminated', 'responseStall', 'adapterBufferFull', 'bufferOverflow'
                )),
                PRIMARY KEY (sessionID, gapOrdinal),
                FOREIGN KEY (sessionID, precedingSegmentOrdinal)
                    REFERENCES connection_session_segments(sessionID, segmentOrdinal) ON DELETE CASCADE,
                FOREIGN KEY (sessionID, followingSegmentOrdinal)
                    REFERENCES connection_session_segments(sessionID, segmentOrdinal) ON DELETE CASCADE
            );
            """)
    }

    /// セグメントに属する受信CANフレームを保持する表を追加します。
    ///
    /// 責務: 29bit識別子と64バイト以下のpayloadをCHECKで守るCANフレーム表を1件作成します。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: テーブル作成に失敗した場合のGRDBエラー。
    nonisolated private static func createConnectionSessionCANFrames(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE connection_session_can_frames (
                sessionID TEXT NOT NULL,
                sequence INTEGER NOT NULL CHECK (sequence >= 0),
                segmentOrdinal INTEGER NOT NULL,
                receivedAtMicroseconds INTEGER NOT NULL,
                monotonicNanoseconds INTEGER NOT NULL CHECK (monotonicNanoseconds >= 0),
                canIdentifier INTEGER NOT NULL CHECK (canIdentifier BETWEEN 0 AND 536870911),
                payload BLOB NOT NULL CHECK (length(payload) <= 64),
                PRIMARY KEY (sessionID, sequence),
                FOREIGN KEY (sessionID, segmentOrdinal)
                    REFERENCES connection_session_segments(sessionID, segmentOrdinal) ON DELETE CASCADE
            );
            """)
    }

    /// 既存Raw表へ所属セグメントと単調時刻のNULL可列を追加します。
    ///
    /// 責務: 既存Raw行を変更せず `segmentOrdinal` と `monotonicNanoseconds` の2列だけを追加します。
    /// - Parameter database: 列を追加するSQLite接続。
    /// - Throws: 列追加に失敗した場合のGRDBエラー。
    nonisolated private static func addConnectionSessionRawLogSegmentColumns(in database: Database) throws {
        try database.execute(sql: """
            ALTER TABLE connection_session_raw_logs ADD COLUMN segmentOrdinal INTEGER;
            ALTER TABLE connection_session_raw_logs ADD COLUMN monotonicNanoseconds INTEGER;
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
            table.check(sql: "(requiredByteCount IS NULL AND formula IS NULL) OR "
                + "(requiredByteCount IS NOT NULL AND formula IS NOT NULL AND length(formula) > 0)")
            table.check(sql: "(minimumValue IS NULL AND maximumValue IS NULL) OR "
                + "(minimumValue IS NOT NULL AND maximumValue IS NOT NULL AND minimumValue <= maximumValue)")
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
            table.check(sql: "(vehicleID IS NULL AND vehicleName IS NULL AND vehicleDisplayIdentifier IS NULL) OR "
                + "(vehicleID IS NOT NULL AND vehicleName IS NOT NULL AND vehicleDisplayIdentifier IS NOT NULL)")
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
