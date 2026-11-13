import Foundation
import GRDB

/// 同期エンジンの状態(変更トークンなど)を直列化したバイト列として `sync_state` に保存します。
nonisolated struct SyncEngineStateStore: Sendable {
    private let database: AppDatabase

    /// `sync_state` 上のキーです。
    static let key = "engine.state"

    /// 責務: 共有データベースへ保存するストアを生成します。
    init(database: AppDatabase) {
        self.database = database
    }

    /// 責務: 保存済みの状態を返します。無ければ `nil` です。
    func load() throws -> Data? {
        try database.writer.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = ?", arguments: [Self.key])
        }
    }

    /// 責務: 状態を保存します。
    func save(_ value: Data) throws {
        try database.writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)", arguments: [Self.key, value])
        }
    }

    /// 責務: 状態を消し、次回は最初から同期するようにします。
    func clear() throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [Self.key])
        }
    }
}
