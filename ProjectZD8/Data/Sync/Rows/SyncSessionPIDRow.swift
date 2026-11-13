import GRDB

/// アーカイブの作成と復元で読み書きする `session_pids` テーブルの1行です。
nonisolated struct SyncSessionPIDRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "session_pids"

    var sessionID: String
    var ordinal: Int
    var service: Int
    var pid: Int
    var header: Int?
    var support: String
    var isCollectionEnabled: Bool
    var isFastGroup: Bool
    var definitionRevision: Int
    var requiredByteCount: Int?
    var formula: String?
    var unit: String
    var minimumValue: Double?
    var maximumValue: Double?
}
