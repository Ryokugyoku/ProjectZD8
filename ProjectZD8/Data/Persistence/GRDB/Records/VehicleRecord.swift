import Foundation
import GRDB

/// `vehicles` テーブルの1行です。
nonisolated struct VehicleRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "vehicles"

    var id: String
    var vin: String
    var obdIdentifier: String?
    var name: String
    var manufacturer: String
    var engineModel: String
    var powertrain: String
    /// `VehicleEnergySource.rawValue` のJSON配列です。
    var energySources: String
    var tankCapacityLiters: Double?
    var modelYear: Int?
    var note: String
    var photoID: String?
    var createdAt: Int64
    var modifiedAt: Int64
    var deletedAt: Int64?

    /// 責務: 車両エンティティから行を生成します。
    init(_ vehicle: Vehicle) throws {
        guard let sources = String(data: try JSONEncoder().encode(vehicle.energySources.map(\.rawValue)), encoding: .utf8) else {
            throw StoreError.ioFailure
        }
        id = vehicle.id.rowID
        vin = vehicle.vin
        obdIdentifier = vehicle.obdIdentifier
        name = vehicle.name
        manufacturer = vehicle.manufacturer
        engineModel = vehicle.engineModel
        powertrain = vehicle.powertrain.rawValue
        energySources = sources
        tankCapacityLiters = vehicle.tankCapacityLiters
        modelYear = vehicle.modelYear
        note = vehicle.note
        photoID = vehicle.photoID?.rowID
        createdAt = vehicle.createdAt.epochMilliseconds
        modifiedAt = vehicle.modifiedAt.epochMilliseconds
        deletedAt = nil
    }

    /// 責務: 行を車両エンティティへ変換します。不正な値は `StoreError.ioFailure` を投げます。
    func entity() throws -> Vehicle {
        guard let powertrainKind = VehiclePowertrainKind(rawValue: powertrain) else { throw StoreError.ioFailure }
        let rawSources = try JSONDecoder().decode([String].self, from: Data(energySources.utf8))
        let sources = try rawSources.map { raw -> VehicleEnergySource in
            guard let source = VehicleEnergySource(rawValue: raw) else { throw StoreError.ioFailure }
            return source
        }
        return Vehicle(
            id: try VehicleID(rowID: id),
            vin: vin,
            obdIdentifier: obdIdentifier,
            name: name,
            manufacturer: manufacturer,
            engineModel: engineModel,
            powertrain: powertrainKind,
            energySources: sources,
            tankCapacityLiters: tankCapacityLiters,
            modelYear: modelYear,
            note: note,
            photoID: try photoID.map { try PhotoID(rowID: $0) },
            createdAt: Date(epochMilliseconds: createdAt),
            modifiedAt: Date(epochMilliseconds: modifiedAt)
        )
    }
}
