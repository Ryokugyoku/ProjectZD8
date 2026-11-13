import Foundation
import GRDB

/// 削除規則を実装します。同期済みの行は墓標化し、未同期の行は物理削除します。
nonisolated enum TombstoneDeletion {
    /// 責務: `sync_records` に行がある場合は `deletedAt` と `modifiedAt` を現在時刻にして墓標化し、無ければ物理削除します。
    static func deleteOrTombstone(table: String, recordType: String, id: String, now: Date, in db: Database) throws {
        let isSynced = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS (SELECT 1 FROM sync_records WHERE recordType = ? AND recordID = ?)",
            arguments: [recordType, id]
        ) ?? false
        if isSynced {
            let milliseconds = now.epochMilliseconds
            try db.execute(sql: "UPDATE \(table) SET deletedAt = ?, modifiedAt = ? WHERE id = ?", arguments: [milliseconds, milliseconds, id])
        } else {
            try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id])
        }
    }

    /// 責務: 子レコードをCloudKitの連鎖削除に任せるため、指定IDの同期管理行を削除します。
    static func removeSyncRows(recordType: String, ids: [String], in db: Database) throws {
        for id in ids {
            try db.execute(sql: "DELETE FROM sync_records WHERE recordType = ? AND recordID = ?", arguments: [recordType, id])
        }
    }
}
