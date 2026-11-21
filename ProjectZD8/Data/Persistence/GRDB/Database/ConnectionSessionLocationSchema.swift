import GRDB

/// 接続セッションの位置サンプルと位置記録事象の表を定義します。
nonisolated enum ConnectionSessionLocationSchema {
    /// 位置サンプル表と位置記録事象表を追加します。
    ///
    /// 責務: 既存の行を変更せず、セッション削除で連動して消える2表を追加します。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: いずれかの文の実行に失敗した場合のGRDBエラー。
    static func create(in database: Database) throws {
        try createSamplesTable(in: database)
        try createEventsTable(in: database)
    }

    /// 位置サンプル表を作成します。
    ///
    /// 責務: 緯度経度・精度・標高と垂直精度の組・速度・進行方向の範囲をCHECKで守る表を1件作成します。
    /// 主キーが読み出し順を兼ねるため、追加の索引は作りません。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createSamplesTable(in database: Database) throws {
        try database.execute(sql: """
            CREATE TABLE connection_session_location_samples (
                sessionID TEXT NOT NULL
                    REFERENCES connection_sessions(id) ON DELETE CASCADE,
                sequence INTEGER NOT NULL CHECK (sequence >= 0),
                observedAtMicroseconds INTEGER NOT NULL,
                monotonicNanoseconds INTEGER NOT NULL CHECK (monotonicNanoseconds >= 0),
                latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
                longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
                altitudeMeters REAL,
                horizontalAccuracyMeters REAL NOT NULL CHECK (horizontalAccuracyMeters >= 0),
                verticalAccuracyMeters REAL CHECK (verticalAccuracyMeters IS NULL OR verticalAccuracyMeters >= 0),
                speedMetersPerSecond REAL CHECK (speedMetersPerSecond IS NULL OR speedMetersPerSecond >= 0),
                courseDegrees REAL CHECK (courseDegrees IS NULL OR (courseDegrees >= 0 AND courseDegrees < 360)),
                CHECK ((altitudeMeters IS NULL) = (verticalAccuracyMeters IS NULL)),
                PRIMARY KEY (sessionID, sequence)
            );
            """)
    }

    /// 位置記録事象表を作成します。
    ///
    /// 責務: 事象の種類を `ConnectionSessionLocationEventKind` の全rawValueに限るCHECK付きの表を1件作成します。
    /// - Parameter database: SQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    private static func createEventsTable(in database: Database) throws {
        let kinds = ConnectionSessionLocationEventKind.allCases
            .map { "'\($0.rawValue)'" }
            .joined(separator: ", ")
        try database.execute(sql: """
            CREATE TABLE connection_session_location_events (
                sessionID TEXT NOT NULL
                    REFERENCES connection_sessions(id) ON DELETE CASCADE,
                eventOrdinal INTEGER NOT NULL CHECK (eventOrdinal >= 0),
                occurredAtMicroseconds INTEGER NOT NULL,
                kind TEXT NOT NULL CHECK (kind IN (\(kinds))),
                PRIMARY KEY (sessionID, eventOrdinal)
            );
            """)
    }
}
