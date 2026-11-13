import GRDB

/// `photos` テーブルの1行です。画像本体は `PhotoFileStore` が保持します。
nonisolated struct PhotoRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "photos"

    var id: String
    var vehicleID: String
    var byteCount: Int
    var createdAt: Int64
    var modifiedAt: Int64
    var deletedAt: Int64?
}
