import Foundation
import GRDB

/// 同期が読み書きする `maintenance_records` テーブルの1行です。列の値をそのまま保持します。
nonisolated struct SyncMaintenanceRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "maintenance_records"

    var id: String
    var vehicleID: String
    var kind: String
    var title: String
    var performedAt: Int64
    var odometerKilometers: Double?
    var notes: String
    /// workItems / photos / fastenerGroups のJSONです。永続化層の形式のまま運びます。
    var detail: Data
    var createdAt: Int64
    var modifiedAt: Int64
    var deletedAt: Int64?
}
