import Foundation
import GRDB

/// 整備記録をGRDBで永続化します。
nonisolated struct GRDBMaintenanceRepository: MaintenanceRepository {
    private let database: AppDatabase
    private let photoFiles: PhotoFileStore
    private let now: @Sendable () -> Date

    /// 責務: 共有データベースと写真ファイルストアを使うリポジトリを生成します。
    init(database: AppDatabase, photoFiles: PhotoFileStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.photoFiles = photoFiles
        self.now = now
    }

    /// 責務: 車両の削除されていない整備記録を実施日の新しい順で返します。
    func records(for vehicleID: VehicleID) async throws -> [MaintenanceRecord] {
        try await database.storeRead { db in
            try MaintenanceRecordRow
                .filter(Column("vehicleID") == vehicleID.rowID && Column("deletedAt") == nil)
                .order(Column("performedAt").desc, Column("createdAt").desc)
                .fetchAll(db)
                .map { try $0.entity() }
        }
    }

    /// 責務: 整備記録を新規保存または上書きします。車両が存在しなければ `StoreError.notFound` を投げます。
    func save(_ record: MaintenanceRecord) async throws {
        let row = try MaintenanceRecordRow(record)
        let vehicleID = record.vehicleID.rowID
        try await database.storeWrite { db in
            guard try VehicleRecord.filter(Column("id") == vehicleID && Column("deletedAt") == nil).fetchCount(db) == 1 else {
                throw StoreError.notFound
            }
            try row.upsert(db)
        }
    }

    /// 責務: 整備記録を削除します。他の記録・車両写真から参照されない写真も削除します。
    func delete(_ id: MaintenanceRecordID) async throws {
        let rowID = id.rowID
        let timestamp = now()
        let removedPhotos = try await database.storeWrite { db -> [PhotoID] in
            guard let row = try MaintenanceRecordRow.filter(Column("id") == rowID && Column("deletedAt") == nil).fetchOne(db) else {
                throw StoreError.notFound
            }
            var orphaned = try MaintenanceRecordDetail.decode(row.detail).referencedPhotoIDs
            let others = try MaintenanceRecordRow
                .filter(Column("vehicleID") == row.vehicleID && Column("id") != rowID && Column("deletedAt") == nil)
                .fetchAll(db)
            for other in others { orphaned.subtract(try MaintenanceRecordDetail.decode(other.detail).referencedPhotoIDs) }
            if let vehiclePhoto = try String.fetchOne(db, sql: "SELECT photoID FROM vehicles WHERE id = ?", arguments: [row.vehicleID]) {
                orphaned.remove(try PhotoID(rowID: vehiclePhoto))
            }
            let existing = try orphaned.filter { photoID in
                try PhotoRecord.filter(Column("id") == photoID.rowID && Column("vehicleID") == row.vehicleID).fetchCount(db) == 1
            }
            try PhotoRowDeletion.remove(existing.map(\.rowID), now: timestamp, in: db)
            try TombstoneDeletion.deleteOrTombstone(
                table: "maintenance_records", recordType: PersistenceRecordType.maintenanceRecord, id: rowID, now: timestamp, in: db
            )
            return Array(existing)
        }
        do {
            for photoID in removedPhotos { try photoFiles.remove(photoID) }
        } catch {
            throw StoreError.ioFailure
        }
    }
}
