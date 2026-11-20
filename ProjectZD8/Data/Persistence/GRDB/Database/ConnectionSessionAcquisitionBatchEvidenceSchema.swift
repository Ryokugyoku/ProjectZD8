import GRDB

/// 取得batchとPID request evidenceの正規化表を定義します。
nonisolated enum ConnectionSessionAcquisitionBatchEvidenceSchema {
    /// 取得batchとPID request evidenceの正規化表を追加します。
    ///
    /// 責務: 既存Raw表を変更せずpartial取得を復元できるbatch/request表と不変性制約を追加します。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: いずれかの文の実行に失敗した場合のGRDBエラー。
    static func create(in database: Database) throws {
        try createBatchesTable(in: database)
        try createPIDRequestsTable(in: database)
        try createIndexes(in: database)
        try createUpdateGuards(in: database)
        try createCompletedBatchGuard(in: database)
    }

    /// 取得batch表を作成します。
    ///
    /// 責務: batch表の列とCHECK制約を追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createBatchesTable(in database: Database) throws {
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
            """)
    }

    /// 取得PID request表を作成します。
    ///
    /// 責務: PID request表の列・外部キー・CHECK制約を追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createPIDRequestsTable(in database: Database) throws {
        try database.execute(sql: """
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
            """)
    }

    /// batchとPID requestの索引を作成します。
    ///
    /// 責務: 完了状態とPID結果の検索用索引を追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createIndexes(in database: Database) throws {
        try database.execute(sql: """
            CREATE INDEX acquisition_batches_session_completion
                ON connection_session_acquisition_batches(sessionID, completionState, batchOrdinal);
            CREATE INDEX acquisition_pid_requests_pid_outcome
                ON connection_session_acquisition_pid_requests(sessionID, manifestPIDOrdinal, transportOutcome);
            """)
    }

    /// batchとrequestの更新不変性triggerを作成します。
    ///
    /// 責務: 封印済み行の更新を拒否するtriggerを追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createUpdateGuards(in database: Database) throws {
        try database.execute(sql: """
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
            """)
    }

    /// 完了batchの連続性triggerを作成します。
    ///
    /// 責務: 完了batchが連続した終端requestを持つことを保証するtriggerを追加します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createCompletedBatchGuard(in database: Database) throws {
        try database.execute(sql: """
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
}
