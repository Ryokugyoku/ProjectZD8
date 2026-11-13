import Foundation
import GRDB

/// 送信側の同期状態をローカルのテーブルから導き、送信結果を書き戻します。
///
/// 未送信の判定: `sync_records` に行が無い、または `modifiedAt > syncedModifiedAt` の行は保存待ち、
/// `deletedAt` が入った行は削除待ちです。セッションは終了済みかつデモ以外だけが対象です。
///
/// Rawがローカルにあるセッションは、アーカイブゾーンへのアップロードが済んで `archiveDigest` が入るまで
/// 属性レコードを送りません。こうして「検証値を公開する前にアーカイブが保存済み」を保証します。
nonisolated struct SyncLocalStore: Sendable {
    private let database: AppDatabase
    private let photoFiles: PhotoFileStore

    /// 責務: 共有データベースと写真ストアを使うストアを生成します。
    init(database: AppDatabase, photoFiles: PhotoFileStore) {
        self.database = database
        self.photoFiles = photoFiles
    }

    // MARK: - 未送信の変更

    /// 責務: 未送信の変更を、親を先・削除を後にした送信順で返します。
    func pendingChanges() throws -> [SyncPendingChange] {
        try database.writer.read { db in try Self.pendingChanges(db) }
    }

    /// 責務: 指定接続で未送信の変更を送信順に求めます。
    static func pendingChanges(_ db: Database) throws -> [SyncPendingChange] {
        var saves: [SyncPendingChange] = []
        var deletions: [SyncPendingChange] = []
        for type in SyncRecordType.allCases.sorted(by: { $0.sendOrder < $1.sendOrder }) {
            let sessionFilter = type == .driveSession
                ? " AND t.endedAt IS NOT NULL AND t.isDemo = 0 AND NOT (t.rawAvailability = '\(RawAvailability.local.rawValue)' AND t.archiveDigest IS NULL)"
                : ""
            let saveIDs = try String.fetchAll(db, sql: """
                SELECT t.id FROM \(type.tableName) t
                LEFT JOIN sync_records s ON s.recordType = ? AND s.recordID = t.id
                WHERE t.deletedAt IS NULL\(sessionFilter)
                  AND (s.recordID IS NULL OR s.syncedModifiedAt IS NULL OR t.modifiedAt > s.syncedModifiedAt)
                ORDER BY t.id
                """, arguments: [type.rawValue])
            saves += saveIDs.map { SyncPendingChange(recordType: type, recordName: $0, kind: .save) }
            let deleteIDs = try String.fetchAll(db, sql: "SELECT id FROM \(type.tableName) WHERE deletedAt IS NOT NULL ORDER BY id")
            deletions += deleteIDs.map { SyncPendingChange(recordType: type, recordName: $0, kind: .delete) }
        }
        // 子の削除を先に、車両の削除を最後にします。
        deletions.sort { $0.recordType.sendOrder > $1.recordType.sendOrder }
        return saves + deletions
    }

    /// 責務: 指定行に未送信の変更があるかどうかと、ローカルの更新日時を返します。行が無ければ `nil` です。
    static func localState(_ db: Database, recordType: SyncRecordType, recordName: String) throws -> (modifiedAt: Int64, deletedAt: Int64?, isPending: Bool)? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT t.modifiedAt, t.deletedAt, s.recordID AS syncedID, s.syncedModifiedAt
            FROM \(recordType.tableName) t
            LEFT JOIN sync_records s ON s.recordType = ? AND s.recordID = t.id
            WHERE t.id = ?
            """, arguments: [recordType.rawValue, recordName]) else { return nil }
        let modifiedAt: Int64 = row["modifiedAt"]
        let deletedAt: Int64? = row["deletedAt"]
        let syncedID: String? = row["syncedID"]
        let syncedModifiedAt: Int64? = row["syncedModifiedAt"]
        let isPending = deletedAt != nil || syncedID == nil || syncedModifiedAt.map { modifiedAt > $0 } ?? true
        return (modifiedAt, deletedAt, isPending)
    }

    /// 責務: 指定行の現在の内容を返します。墓標行も返します。行が無ければ `nil` です。
    static func payload(_ db: Database, recordType: SyncRecordType, recordName: String) throws -> (payload: SyncRecordPayload, deletedAt: Int64?)? {
        switch recordType {
        case .vehicle:
            return try SyncVehicleRow.fetchOne(db, key: recordName).map { (.vehicle($0), $0.deletedAt) }
        case .maintenanceRecord:
            return try SyncMaintenanceRow.fetchOne(db, key: recordName).map { (.maintenanceRecord($0), $0.deletedAt) }
        case .photo:
            return try SyncPhotoRow.fetchOne(db, key: recordName).map { (.photo($0), $0.deletedAt) }
        case .driveSession:
            return try SyncSessionRow.fetchOne(db, key: recordName).map { (.driveSession($0), $0.deletedAt) }
        }
    }

    // MARK: - 送信

    /// 責務: 保存待ちの行から送信するレコードの材料を作ります。
    /// - Returns: 保存待ちでない(送信済み・削除待ち・同期対象外・アーカイブ未アップロード・行が無い)場合は `nil`。
    func outgoingRecord(recordType: SyncRecordType, recordName: String) throws -> SyncOutgoingRecord? {
        let loaded: (SyncRecordPayload, Data?)? = try database.writer.read { db in
            guard let state = try Self.localState(db, recordType: recordType, recordName: recordName),
                  state.deletedAt == nil, state.isPending,
                  let current = try Self.payload(db, recordType: recordType, recordName: recordName) else { return nil }
            if case .driveSession(let row) = current.payload,
               !row.isSyncable || (row.rawAvailability == RawAvailability.local.rawValue && row.archiveDigest == nil) {
                return nil
            }
            let metadata = try SyncRecordMetadataRow.fetchOne(db, key: ["recordType": recordType.rawValue, "recordID": recordName])
            return (current.payload, metadata?.systemFields)
        }
        guard let (payload, systemFields) = loaded else { return nil }
        switch payload {
        case .photo(let row):
            guard let uuid = UUID(uuidString: row.id) else { throw SyncLocalStoreError.invalidValue("id") }
            let url = photoFiles.url(for: PhotoID(rawValue: uuid))
            let exists = FileManager.default.fileExists(atPath: url.path)
            return SyncOutgoingRecord(payload: payload, systemFields: systemFields, photoFileURL: exists ? url : nil)
        default:
            return SyncOutgoingRecord(payload: payload, systemFields: systemFields)
        }
    }

    /// 責務: 保存の成功を記録します。送信後にさらに更新された行は引き続き保存待ちになります。
    /// - Parameters:
    ///   - systemFields: サーバーが返したレコードのシステムフィールド。
    ///   - sentModifiedAt: 送信したレコードの `modifiedAt`。
    /// - Returns: ローカル行が既に無い場合は `false`(サーバー側の削除が必要)。
    @discardableResult
    func markSaved(recordType: SyncRecordType, recordName: String, systemFields: Data, sentModifiedAt: Int64) throws -> Bool {
        try database.writer.write { db in
            guard try Self.localState(db, recordType: recordType, recordName: recordName) != nil else { return false }
            let existing = try SyncRecordMetadataRow.fetchOne(db, key: ["recordType": recordType.rawValue, "recordID": recordName])
            let synced = max(existing?.syncedModifiedAt ?? sentModifiedAt, sentModifiedAt)
            try SyncRecordMetadataRow(recordType: recordType.rawValue, recordID: recordName, systemFields: systemFields, syncedModifiedAt: synced).save(db)
            return true
        }
    }

    /// 責務: サーバーでの削除完了を記録し、墓標行と同期管理行を物理削除します。
    ///
    /// セッションなら、そのアーカイブを削除待ちへ移します。車両なら、索引にあるその車両の全アーカイブを削除待ちへ移します。
    func markDeletionConfirmed(recordType: SyncRecordType, recordName: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM \(recordType.tableName) WHERE id = ? AND deletedAt IS NOT NULL", arguments: [recordName])
            try SyncRecordMetadataRow.deleteOne(db, key: ["recordType": recordType.rawValue, "recordID": recordName])
            switch recordType {
            case .driveSession: try SyncArchiveIndex.enqueueDeletion(db, sessionID: recordName)
            case .vehicle: try SyncArchiveIndex.enqueueDeletions(db, vehicleID: recordName)
            case .maintenanceRecord, .photo: break
            }
        }
    }

    // MARK: - アーカイブ

    /// 責務: アーカイブのアップロードを待つセッション(終了済み・デモ以外・Rawローカル・検証値なし)のIDを開始順に返します。
    func pendingArchiveUploads() throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM sessions
                WHERE deletedAt IS NULL AND endedAt IS NOT NULL AND isDemo = 0
                  AND rawAvailability = ? AND archiveDigest IS NULL
                ORDER BY startedAt, id
                """, arguments: [RawAvailability.local.rawValue])
        }
    }

    /// 責務: アーカイブレコードの保存成功を記録します。検証値を入れて属性レコードを送信待ちにし、索引へ登録します。
    ///
    /// 検証値の設定はRawの所在の記録で、`modifiedAt` は変えません。行が既に無くても索引には登録し、
    /// 次の照合で削除待ちへ移るようにします。
    func markArchiveUploaded(sessionID: String, vehicleID: String, digest: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE sessions SET archiveDigest = ? WHERE id = ? AND archiveDigest IS NULL", arguments: [digest, sessionID])
            try SyncArchiveIndex.record(db, sessionID: sessionID, vehicleID: vehicleID)
        }
    }

    /// 責務: サーバー上の版を示すシステムフィールドだけを差し替えます。同期済み時点は変えません。
    /// - Parameter systemFields: 新しいシステムフィールド。`nil` ならサーバーに無いものとして次回は新規作成します。
    func replaceSystemFields(recordType: SyncRecordType, recordName: String, systemFields: Data?) throws {
        try database.writer.write { db in
            let existing = try SyncRecordMetadataRow.fetchOne(db, key: ["recordType": recordType.rawValue, "recordID": recordName])
            try SyncRecordMetadataRow(
                recordType: recordType.rawValue,
                recordID: recordName,
                systemFields: systemFields,
                syncedModifiedAt: existing?.syncedModifiedAt
            ).save(db)
        }
    }

    /// 責務: レコード名(UUID)から、そのレコードの種類を探します。
    func recordType(forRecordName recordName: String) throws -> SyncRecordType? {
        try database.writer.read { db in
            if let raw = try String.fetchOne(db, sql: "SELECT recordType FROM sync_records WHERE recordID = ?", arguments: [recordName]),
               let type = SyncRecordType(rawValue: raw) {
                return type
            }
            for type in SyncRecordType.allCases {
                if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM \(type.tableName) WHERE id = ?)", arguments: [recordName]) == true {
                    return type
                }
            }
            return nil
        }
    }

    /// 責務: 全ローカルデータを未送信に戻します(サインイン直後や暗号化データのリセット時)。
    ///
    /// 新しいアカウントのサーバーには何も無いため、墓標行は物理削除し、同期管理行と保留中の子レコードを捨て、
    /// Rawがローカルにあるセッションはアーカイブを送り直すよう検証値を消します。
    /// Rawが `cloudOnly` のセッションは検証値を保ちます(エンジンの状態だけがリセットされた場合、
    /// アーカイブはエンジン管理外のアーカイブゾーンに残っているため)。アーカイブの索引と削除待ちも保ちます。
    func resetForReupload() throws {
        try database.writer.write { db in
            for type in SyncRecordType.allCases.sorted(by: { $0.sendOrder > $1.sendOrder }) {
                try db.execute(sql: "DELETE FROM \(type.tableName) WHERE deletedAt IS NOT NULL")
            }
            try db.execute(sql: "DELETE FROM sync_records")
            try db.execute(sql: "DELETE FROM sync_state WHERE key LIKE ?", arguments: ["\(SyncParkedRecord.keyPrefix)%"])
            try db.execute(sql: "UPDATE sessions SET archiveDigest = NULL WHERE rawAvailability = ?", arguments: [RawAvailability.local.rawValue])
        }
    }
}
