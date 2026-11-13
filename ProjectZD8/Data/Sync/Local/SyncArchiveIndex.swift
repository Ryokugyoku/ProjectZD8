import Foundation
import GRDB

/// iCloud上にあると分かっているRawアーカイブの索引と、削除待ちのアーカイブの列を `sync_state` に保持します。
///
/// アーカイブはエンジン管理外のゾーンにあり、親車両への削除連鎖参照を持てません。
/// そのため車両やセッションが消えた時は、この索引から対象を求めてアプリが直接削除します。
/// 削除に失敗したものは列に残り、次の同期で再試行します。
///
/// - 索引: `archive.index.<セッションID>` → `Entry` のJSON
/// - 削除待ち: `archive.delete.<セッションID>` → `Entry` のJSON
nonisolated struct SyncArchiveIndex: Sendable {
    /// 1件のアーカイブの所属です。
    nonisolated struct Entry: Codable, Equatable, Sendable {
        let sessionID: String
        let vehicleID: String

        /// 責務: アーカイブの所属をまとめます。
        init(sessionID: String, vehicleID: String) {
            self.sessionID = sessionID
            self.vehicleID = vehicleID
        }
    }

    /// 索引のキーの接頭辞です。
    static let indexPrefix = "archive.index."
    /// 削除待ちのキーの接頭辞です。
    static let deletionPrefix = "archive.delete."

    private let database: AppDatabase

    /// 責務: 共有データベースに索引を保持する型を生成します。
    init(database: AppDatabase) {
        self.database = database
    }

    /// 責務: 索引の全項目をセッションID順に返します。
    func entries() throws -> [Entry] {
        try database.writer.read { db in try Self.entries(db, prefix: Self.indexPrefix) }
    }

    /// 責務: 削除待ちの全項目をセッションID順に返します。
    func queuedDeletions() throws -> [Entry] {
        try database.writer.read { db in try Self.entries(db, prefix: Self.deletionPrefix) }
    }

    /// 責務: セッション行が無くなったアーカイブを削除待ちへ移します。
    func reconcile() throws {
        try database.writer.write { db in try Self.reconcile(db) }
    }

    /// 責務: 削除が済んだ(またはサーバーに無かった)アーカイブを削除待ちから外します。
    func deletionsCompleted(sessionIDs: [String]) throws {
        try database.writer.write { db in
            for id in sessionIDs {
                try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [Self.deletionPrefix + id])
            }
        }
    }

    // MARK: - 接続内の処理

    /// 責務: アップロード済み、またはリモートから知ったアーカイブを索引へ登録します。同じセッションの削除待ちは取り消します。
    static func record(_ db: Database, sessionID: String, vehicleID: String) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)",
                       arguments: [indexPrefix + sessionID, try JSONEncoder().encode(Entry(sessionID: sessionID, vehicleID: vehicleID))])
        try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [deletionPrefix + sessionID])
    }

    /// 責務: 索引にあるセッションのアーカイブを削除待ちへ移します。索引に無ければ何もしません。
    static func enqueueDeletion(_ db: Database, sessionID: String) throws {
        guard let value = try Data.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = ?", arguments: [indexPrefix + sessionID]) else { return }
        try db.execute(sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)", arguments: [deletionPrefix + sessionID, value])
        try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [indexPrefix + sessionID])
    }

    /// 責務: 索引にある指定車両の全アーカイブを削除待ちへ移します。
    static func enqueueDeletions(_ db: Database, vehicleID: String) throws {
        for entry in try entries(db, prefix: indexPrefix) where entry.vehicleID == vehicleID {
            try enqueueDeletion(db, sessionID: entry.sessionID)
        }
    }

    /// 責務: セッション行が存在しない索引項目を削除待ちへ移します(永続化層による物理削除の取りこぼしを防ぎます)。
    static func reconcile(_ db: Database) throws {
        for entry in try entries(db, prefix: indexPrefix)
        where try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM sessions WHERE id = ?)", arguments: [entry.sessionID]) != true {
            try enqueueDeletion(db, sessionID: entry.sessionID)
        }
    }

    /// 責務: 指定接頭辞の項目を読みます。
    private static func entries(_ db: Database, prefix: String) throws -> [Entry] {
        let decoder = JSONDecoder()
        return try Data.fetchAll(db, sql: "SELECT value FROM sync_state WHERE key LIKE ? ORDER BY key", arguments: ["\(prefix)%"])
            .map { try decoder.decode(Entry.self, from: $0) }
    }
}
