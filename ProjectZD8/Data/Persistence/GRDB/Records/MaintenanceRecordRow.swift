import Foundation
import GRDB

/// `maintenance_records` テーブルの1行です。
nonisolated struct MaintenanceRecordRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "maintenance_records"

    var id: String
    var vehicleID: String
    var kind: String
    var title: String
    var performedAt: Int64
    var odometerKilometers: Double?
    var notes: String
    /// `MaintenanceRecordDetail` のJSONです。
    var detail: Data
    var createdAt: Int64
    var modifiedAt: Int64
    var deletedAt: Int64?

    /// 責務: 整備記録エンティティから行を生成します。
    init(_ record: MaintenanceRecord) throws {
        id = record.id.rowID
        vehicleID = record.vehicleID.rowID
        kind = record.kind.rawValue
        title = record.title
        performedAt = record.performedAt.epochMilliseconds
        odometerKilometers = record.odometerKilometers
        notes = record.notes
        detail = try MaintenanceRecordDetail(record).encoded()
        createdAt = record.createdAt.epochMilliseconds
        modifiedAt = record.modifiedAt.epochMilliseconds
        deletedAt = nil
    }

    /// 責務: 行を整備記録エンティティへ変換します。不正な値は `StoreError.ioFailure` を投げます。
    func entity() throws -> MaintenanceRecord {
        guard let kind = MaintenanceKind(rawValue: kind) else { throw StoreError.ioFailure }
        let detail = try MaintenanceRecordDetail.decode(detail)
        return MaintenanceRecord(
            id: try MaintenanceRecordID(rowID: id),
            vehicleID: try VehicleID(rowID: vehicleID),
            kind: kind,
            title: title,
            performedAt: Date(epochMilliseconds: performedAt),
            odometerKilometers: odometerKilometers,
            notes: notes,
            workItems: detail.workItems,
            photos: detail.photos,
            fastenerGroups: detail.fastenerGroups,
            createdAt: Date(epochMilliseconds: createdAt),
            modifiedAt: Date(epochMilliseconds: modifiedAt)
        )
    }
}
