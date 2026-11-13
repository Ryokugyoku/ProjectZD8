import Foundation
import GRDB

/// 登録車両をGRDBで永続化します。
nonisolated struct GRDBVehicleRepository: VehicleRepository {
    private let database: AppDatabase
    private let photoFiles: PhotoFileStore
    private let now: @Sendable () -> Date

    /// 責務: 共有データベースと写真ファイルストアを使うリポジトリを生成します。
    init(database: AppDatabase, photoFiles: PhotoFileStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.database = database
        self.photoFiles = photoFiles
        self.now = now
    }

    /// 責務: 削除されていない全車両を名称順で返します。
    func vehicles() async throws -> [Vehicle] {
        try await database.storeRead { db in
            try VehicleRecord
                .filter(Column("deletedAt") == nil)
                .order(Column("name").collating(.localizedCaseInsensitiveCompare), Column("createdAt"))
                .fetchAll(db)
                .map { try $0.entity() }
        }
    }

    /// 責務: IDに一致する削除されていない車両を返します。
    func vehicle(_ id: VehicleID) async throws -> Vehicle? {
        try await database.storeRead { db in
            try VehicleRecord
                .filter(Column("id") == id.rowID && Column("deletedAt") == nil)
                .fetchOne(db)?
                .entity()
        }
    }

    /// 責務: 車両を新規保存または上書きします。墓標化された同一IDは復活させます。
    func save(_ vehicle: Vehicle) async throws {
        let record = try VehicleRecord(vehicle)
        try await database.storeWrite { db in
            try record.upsert(db)
        }
    }

    /// 責務: 車両と子データ(セッション・整備記録・写真・PID設定)を削除します。車両行は同期済みなら墓標化、未同期なら物理削除します。
    func delete(_ id: VehicleID) async throws {
        let vehicleID = id.rowID
        let timestamp = now()
        let photoIDs = try await database.storeWrite { db -> [String] in
            guard try VehicleRecord.filter(Column("id") == vehicleID && Column("deletedAt") == nil).fetchCount(db) == 1 else {
                throw StoreError.notFound
            }
            let photoIDs = try String.fetchAll(db, sql: "SELECT id FROM photos WHERE vehicleID = ?", arguments: [vehicleID])
            let maintenanceIDs = try String.fetchAll(db, sql: "SELECT id FROM maintenance_records WHERE vehicleID = ?", arguments: [vehicleID])
            let sessionIDs = try String.fetchAll(db, sql: "SELECT id FROM sessions WHERE vehicleID = ?", arguments: [vehicleID])

            try TombstoneDeletion.removeSyncRows(recordType: PersistenceRecordType.photo, ids: photoIDs, in: db)
            try TombstoneDeletion.removeSyncRows(recordType: PersistenceRecordType.maintenanceRecord, ids: maintenanceIDs, in: db)
            try TombstoneDeletion.removeSyncRows(recordType: PersistenceRecordType.driveSession, ids: sessionIDs, in: db)

            for sessionID in sessionIDs {
                try db.execute(sql: "DELETE FROM session_samples WHERE sessionID = ?", arguments: [sessionID])
                try db.execute(sql: "DELETE FROM session_pids WHERE sessionID = ?", arguments: [sessionID])
            }
            try db.execute(sql: "DELETE FROM sessions WHERE vehicleID = ?", arguments: [vehicleID])
            try db.execute(sql: "DELETE FROM maintenance_records WHERE vehicleID = ?", arguments: [vehicleID])
            try db.execute(sql: "DELETE FROM photos WHERE vehicleID = ?", arguments: [vehicleID])
            try db.execute(sql: "DELETE FROM vehicle_pid_settings WHERE vehicleID = ?", arguments: [vehicleID])
            try TombstoneDeletion.deleteOrTombstone(
                table: "vehicles", recordType: PersistenceRecordType.vehicle, id: vehicleID, now: timestamp, in: db
            )
            return photoIDs
        }
        do {
            for photoID in photoIDs { try photoFiles.remove(try PhotoID(rowID: photoID)) }
        } catch {
            throw StoreError.ioFailure
        }
    }
}
