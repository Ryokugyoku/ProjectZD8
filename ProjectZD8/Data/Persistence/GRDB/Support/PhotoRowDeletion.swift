import Foundation
import GRDB

/// 写真行の削除を共通化します。
nonisolated enum PhotoRowDeletion {
    /// 責務: 指定した写真行を削除規則(同期済みは墓標化、未同期は物理削除)に従って削除します。
    static func remove(_ ids: [String], now: Date, in db: Database) throws {
        for id in ids {
            try TombstoneDeletion.deleteOrTombstone(table: "photos", recordType: PersistenceRecordType.photo, id: id, now: now, in: db)
        }
    }
}
