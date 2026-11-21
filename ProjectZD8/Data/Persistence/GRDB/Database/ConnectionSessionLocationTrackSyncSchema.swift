import GRDB

/// 走行ルートの同期記録の表を定義します。
nonisolated enum ConnectionSessionLocationTrackSyncSchema {
    /// 同期記録表を追加します。
    ///
    /// 責務: 既存の行を変更せず、セッション削除で連動して消える同期記録表を1件追加します。
    /// 同期状態は列で持たず、水位の比較で導出します。主キーが検索を兼ねるため、追加の索引は作りません。
    /// - Parameter database: テーブルを追加するSQLite接続。
    /// - Throws: 文の実行に失敗した場合のGRDBエラー。
    static func create(in database: Database) throws {
        let origins = ConnectionSessionLocationTrackSyncOrigin.allCases
            .map { "'\($0.rawValue)'" }
            .joined(separator: ", ")
        try database.execute(sql: """
            CREATE TABLE connection_session_location_track_sync_states (
                sessionID TEXT PRIMARY KEY NOT NULL
                    REFERENCES connection_sessions(id) ON DELETE CASCADE,
                origin TEXT NOT NULL CHECK (origin IN (\(origins))),
                manifestDigest TEXT NOT NULL CHECK (length(manifestDigest) = 64),
                sampleCount INTEGER NOT NULL CHECK (sampleCount >= 0),
                lastSampleSequence INTEGER CHECK (lastSampleSequence IS NULL OR lastSampleSequence >= 0),
                eventCount INTEGER NOT NULL CHECK (eventCount >= 0),
                lastEventOrdinal INTEGER CHECK (lastEventOrdinal IS NULL OR lastEventOrdinal >= 0),
                syncedAtMicroseconds INTEGER NOT NULL,
                CHECK ((sampleCount = 0) = (lastSampleSequence IS NULL)),
                CHECK ((eventCount = 0) = (lastEventOrdinal IS NULL)),
                CHECK (sampleCount + eventCount > 0)
            );
            """)
    }
}
