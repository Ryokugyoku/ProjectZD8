import Foundation
@testable import ProjectZD8

/// メモリ上の `VehicleRepository` です。
final class DriveFlowVehicleRepository: VehicleRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [Vehicle]
    private var failSave = false

    init(vehicles: [Vehicle] = []) { rows = vehicles }

    /// 責務: 保存の失敗を注入します。
    func configure(failSave: Bool) { lock.withLock { self.failSave = failSave } }

    var saved: [Vehicle] { lock.withLock { rows } }

    func vehicles() async throws -> [Vehicle] { saved }
    func vehicle(_ id: VehicleID) async throws -> Vehicle? { saved.first { $0.id == id } }
    func save(_ vehicle: Vehicle) async throws {
        try lock.withLock {
            if failSave { throw StoreError.ioFailure }
            rows.removeAll { $0.id == vehicle.id }
            rows.append(vehicle)
        }
    }
    func delete(_ id: VehicleID) async throws { lock.withLock { rows.removeAll { $0.id == id } } }
}
