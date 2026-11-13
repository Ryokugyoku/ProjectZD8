import Foundation
import GRDB

/// アーカイブの作成と復元で読み書きする `session_samples` テーブルの1行です。
nonisolated struct SyncSessionSampleRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "session_samples"

    var sessionID: String
    var sequence: Int64
    var tick: Int
    var elapsedMicroseconds: Int64
    var service: Int
    var pid: Int
    /// `SampleOutcome.rawValue` です。
    var outcome: Int
    var payload: Data
}
