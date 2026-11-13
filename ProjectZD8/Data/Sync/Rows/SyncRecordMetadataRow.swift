import Foundation
import GRDB

/// `sync_records` テーブルの1行です。レコードごとのCloudKitシステムフィールドと同期済み時点を保持します。
nonisolated struct SyncRecordMetadataRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_records"

    var recordType: String
    var recordID: String
    /// `CKRecord.encodeSystemFields(with:)` の出力です。サーバー上の版が不明なら `nil` です。
    var systemFields: Data?
    /// 最後にサーバーと一致させた時点の `modifiedAt` です。
    var syncedModifiedAt: Int64?
}
