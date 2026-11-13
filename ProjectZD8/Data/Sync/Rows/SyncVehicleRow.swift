import GRDB

/// 同期が読み書きする `vehicles` テーブルの1行です。列の値をそのまま保持します。
nonisolated struct SyncVehicleRow: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "vehicles"

    var id: String
    var vin: String
    var obdIdentifier: String?
    var name: String
    var manufacturer: String
    var engineModel: String
    var powertrain: String
    /// `VehicleEnergySource.rawValue` のJSON配列文字列です。
    var energySources: String
    var tankCapacityLiters: Double?
    var modelYear: Int?
    var note: String
    var photoID: String?
    /// UTCのUnixエポックからのミリ秒です。
    var createdAt: Int64
    var modifiedAt: Int64
    var deletedAt: Int64?
}
