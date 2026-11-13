import GRDB

/// 同期が読み書きする `photos` テーブルの1行です。画像本体は `PhotoFileStore` にあります。
nonisolated struct SyncPhotoRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "photos"

    var id: String
    var vehicleID: String
    var byteCount: Int
    var createdAt: Int64
    var modifiedAt: Int64
    var deletedAt: Int64?
}
