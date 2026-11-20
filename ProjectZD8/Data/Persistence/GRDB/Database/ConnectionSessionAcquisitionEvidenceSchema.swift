import GRDB

/// 取得manifest、PID snapshot、要求順、Raw境界の正規化表を定義します。
nonisolated enum ConnectionSessionAcquisitionEvidenceSchema {
    /// 取得manifest、PID snapshot、要求順、Raw境界の正規化表を追加します。
    ///
    /// 責務: 既存セッションとRaw行を変更せず取得証拠用の4表と不変性triggerを追加します。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: いずれかの文の実行に失敗した場合のGRDBエラー。
    static func create(in database: Database) throws {
        try createManifestAndDefinitionTables(in: database)
        try createOrderedPIDAndRawBoundaryTables(in: database)
        try createManifestUpdateGuard(in: database)
        try createDefinitionAndOrderedPIDGuards(in: database)
        try createBoundaryInsertGuards(in: database)
    }

    /// manifest表とPID定義表を作成します。
    ///
    /// 責務: 取得manifestとPID snapshot定義の列・制約を追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createManifestAndDefinitionTables(in database: Database) throws {
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
            """)
    }

    /// 要求順表とRaw境界表を作成します。
    ///
    /// 責務: PID要求順とRaw取得境界の列・制約を追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createOrderedPIDAndRawBoundaryTables(in database: Database) throws {
        try database.execute(sql: """
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
            """)
    }

    /// manifest更新不変性triggerを作成します。
    ///
    /// 責務: manifestの封印遷移以外の更新を拒否するtriggerを追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createManifestUpdateGuard(in database: Database) throws {
        try database.execute(sql: """
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
            """)
    }

    /// PID定義・要求順・Raw境界の不変性triggerを作成します。
    ///
    /// 責務: 封印後のinsertと全updateを拒否するtriggerを追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createDefinitionAndOrderedPIDGuards(in database: Database) throws {
        try database.execute(sql: """
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
            """)
    }

    /// Raw境界のinsert検証triggerを作成します。
    ///
    /// 責務: startedとendedの境界追加条件を検証するtriggerを追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createBoundaryInsertGuards(in database: Database) throws {
        try database.execute(sql: """
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
}
