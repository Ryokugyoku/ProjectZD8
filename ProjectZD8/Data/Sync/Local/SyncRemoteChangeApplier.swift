import Foundation
import GRDB

/// iCloudから取得した変更をローカルのテーブルへ適用します。
///
/// - 後勝ち: ローカルに未送信の変更があり、そちらの `modifiedAt` が新しければローカルを残します。
/// - リモートの内容はリモートの `modifiedAt` のまま書き込み、同じトランザクションで同期済みにするので送り返しません。
/// - 親の車両より先に届いた子レコードは `sync_state` に保留し、車両を適用した時に取り込みます。
/// - 検証値付きのセッションはアーカイブの索引へ登録し、削除の適用ではアーカイブを削除待ちへ移します。
nonisolated struct SyncRemoteChangeApplier: Sendable {
    private let database: AppDatabase
    private let photoFiles: PhotoFileStore
    private let resolver: SyncConflictResolver

    /// 責務: 共有データベースと写真ストアへ適用する適用器を生成します。
    init(database: AppDatabase, photoFiles: PhotoFileStore, resolver: SyncConflictResolver = SyncConflictResolver()) {
        self.database = database
        self.photoFiles = photoFiles
        self.resolver = resolver
    }

    /// 責務: 1件のリモートレコードを適用します。
    /// - Parameters:
    ///   - payload: レコードの内容。
    ///   - systemFields: レコードのシステムフィールド。
    ///   - photoImage: 写真レコードの画像データ。写真以外は `nil`。
    /// - Throws: 書き込みに失敗した場合のエラー。
    @discardableResult
    func apply(_ payload: SyncRecordPayload, systemFields: Data, photoImage: Data? = nil) throws -> SyncApplyOutcome {
        if case .photo(let row) = payload, let photoImage {
            try photoFiles.write(photoImage, for: try Self.photoID(row.id))
        }
        return try database.writer.write { db in
            try Self.apply(db, payload: payload, systemFields: systemFields, resolver: resolver)
        }
    }

    /// 責務: リモートでの削除を適用し、行・同期管理行・保留中の子・写真ファイルを消し、アーカイブを削除待ちへ移します。
    func applyDeletion(recordType: SyncRecordType, recordName: String) throws {
        let removedPhotoIDs: [String] = try database.writer.write { db in
            try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [SyncParkedRecord.key(recordType: recordType, recordName: recordName)])
            switch recordType {
            case .vehicle:
                let photoIDs = try String.fetchAll(db, sql: "SELECT id FROM photos WHERE vehicleID = ?", arguments: [recordName])
                for child in SyncRecordType.allCases where child.isVehicleChild {
                    try db.execute(sql: """
                        DELETE FROM sync_records WHERE recordType = ?
                          AND recordID IN (SELECT id FROM \(child.tableName) WHERE vehicleID = ?)
                        """, arguments: [child.rawValue, recordName])
                }
                for parked in try Self.parkedRecords(db) where parked.payload.parentVehicleID == recordName {
                    try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [SyncParkedRecord.key(recordType: parked.payload.recordType, recordName: parked.payload.recordName)])
                }
                try SyncArchiveIndex.enqueueDeletions(db, vehicleID: recordName)
                try db.execute(sql: "DELETE FROM vehicles WHERE id = ?", arguments: [recordName])
                try SyncRecordMetadataRow.deleteOne(db, key: ["recordType": recordType.rawValue, "recordID": recordName])
                return photoIDs
            case .maintenanceRecord, .photo, .driveSession:
                if recordType == .driveSession { try SyncArchiveIndex.enqueueDeletion(db, sessionID: recordName) }
                try db.execute(sql: "DELETE FROM \(recordType.tableName) WHERE id = ?", arguments: [recordName])
                try SyncRecordMetadataRow.deleteOne(db, key: ["recordType": recordType.rawValue, "recordID": recordName])
                return recordType == .photo ? [recordName] : []
            }
        }
        for id in removedPhotoIDs {
            try photoFiles.remove(try Self.photoID(id))
        }
    }

    /// 責務: 保留中の子レコードを全て返します。
    func parkedRecords() throws -> [SyncParkedRecord] {
        try database.writer.read { db in try Self.parkedRecords(db) }
    }

    // MARK: - 接続内の処理

    /// 責務: 指定接続で1件のリモートレコードを適用します。車両なら保留中の子も取り込みます。
    private static func apply(_ db: Database, payload: SyncRecordPayload, systemFields: Data, resolver: SyncConflictResolver) throws -> SyncApplyOutcome {
        let type = payload.recordType
        let name = payload.recordName
        if let vehicleID = payload.parentVehicleID {
            let vehicleDeletedAt = try Row.fetchOne(db, sql: "SELECT deletedAt FROM vehicles WHERE id = ?", arguments: [vehicleID])
            guard let vehicleDeletedAt else {
                let parked = SyncParkedRecord(payload: payload, systemFields: systemFields)
                try db.execute(
                    sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)",
                    arguments: [SyncParkedRecord.key(recordType: type, recordName: name), try JSONEncoder().encode(parked)]
                )
                return .parked
            }
            if (vehicleDeletedAt["deletedAt"] as Int64?) != nil { return .ignored }
        }

        let local = try SyncLocalStore.localState(db, recordType: type, recordName: name)
        let resolution = resolver.resolve(localModifiedAt: local?.modifiedAt, localIsPending: local?.isPending ?? false, remoteModifiedAt: payload.modifiedAt)
        let metadataKey: [String: (any DatabaseValueConvertible)?] = ["recordType": type.rawValue, "recordID": name]
        switch resolution {
        case .keepLocal:
            let existing = try SyncRecordMetadataRow.fetchOne(db, key: metadataKey)
            try SyncRecordMetadataRow(recordType: type.rawValue, recordID: name, systemFields: systemFields, syncedModifiedAt: existing?.syncedModifiedAt).save(db)
            return .keptLocal
        case .applyRemote:
            try write(db, payload: payload)
            try SyncRecordMetadataRow(recordType: type.rawValue, recordID: name, systemFields: systemFields, syncedModifiedAt: payload.modifiedAt).save(db)
            try db.execute(sql: "DELETE FROM sync_state WHERE key = ?", arguments: [SyncParkedRecord.key(recordType: type, recordName: name)])
            if type == .vehicle {
                for parked in try parkedRecords(db) where parked.payload.parentVehicleID == name {
                    _ = try apply(db, payload: parked.payload, systemFields: parked.systemFields, resolver: resolver)
                }
            }
            return .applied
        }
    }

    /// 責務: リモートの内容で行を挿入または更新します。端末ローカルの列は既存の値を保ちます。
    private static func write(_ db: Database, payload: SyncRecordPayload) throws {
        switch payload {
        case .vehicle(var row):
            row.deletedAt = nil
            try row.save(db)
        case .maintenanceRecord(var row):
            row.deletedAt = nil
            try row.save(db)
        case .photo(var row):
            row.deletedAt = nil
            try row.save(db)
        case .driveSession(var row):
            row.deletedAt = nil
            if let existing = try SyncSessionRow.fetchOne(db, key: row.id) {
                row.rawAvailability = existing.rawAvailability
                if existing.rawAvailability == RawAvailability.local.rawValue {
                    // ローカルのRawの件数を正とします。
                    row.sampleCount = existing.sampleCount
                    row.respondedCount = existing.respondedCount
                    row.payloadByteCount = existing.payloadByteCount
                }
            } else {
                row.rawAvailability = RawAvailability.cloudOnly.rawValue
            }
            try row.save(db)
            if row.archiveDigest != nil {
                try SyncArchiveIndex.record(db, sessionID: row.id, vehicleID: row.vehicleID)
            }
        }
    }

    /// 責務: 指定接続で保留中の子レコードを全て読みます。
    private static func parkedRecords(_ db: Database) throws -> [SyncParkedRecord] {
        let values = try Data.fetchAll(db, sql: "SELECT value FROM sync_state WHERE key LIKE ? ORDER BY key", arguments: ["\(SyncParkedRecord.keyPrefix)%"])
        let decoder = JSONDecoder()
        return try values.map { try decoder.decode(SyncParkedRecord.self, from: $0) }
    }

    /// 責務: 写真IDの文字列を写真IDへ変換します。
    private static func photoID(_ raw: String) throws -> PhotoID {
        guard let uuid = UUID(uuidString: raw) else { throw SyncLocalStoreError.invalidValue("photo id") }
        return PhotoID(rawValue: uuid)
    }
}
