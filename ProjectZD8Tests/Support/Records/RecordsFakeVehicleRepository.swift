import Foundation
import Synchronization
@testable import ProjectZD8

/// メモリ上のテスト用 `VehicleRepository` です。
final class RecordsFakeVehicleRepository: VehicleRepository, Sendable {
    private let state: Mutex<State>

    private struct State {
        var vehicles: [Vehicle]
        var deleted: [VehicleID] = []
        var error: StoreError?
    }

    init(vehicles: [Vehicle] = []) {
        state = Mutex(State(vehicles: vehicles))
    }

    var stored: [Vehicle] { state.withLock { $0.vehicles } }
    var deletedIDs: [VehicleID] { state.withLock { $0.deleted } }
    /// 設定すると以後の全呼び出しがこのエラーで失敗します。
    func setError(_ error: StoreError?) { state.withLock { $0.error = error } }
    func replace(_ vehicles: [Vehicle]) { state.withLock { $0.vehicles = vehicles } }

    func vehicles() async throws -> [Vehicle] {
        try state.withLock { s in
            if let error = s.error { throw error }
            return s.vehicles.sorted { $0.name < $1.name }
        }
    }

    func vehicle(_ id: VehicleID) async throws -> Vehicle? {
        try state.withLock { s in
            if let error = s.error { throw error }
            return s.vehicles.first { $0.id == id }
        }
    }

    func save(_ vehicle: Vehicle) async throws {
        try state.withLock { s in
            if let error = s.error { throw error }
            if let index = s.vehicles.firstIndex(where: { $0.id == vehicle.id }) {
                s.vehicles[index] = vehicle
            } else {
                s.vehicles.append(vehicle)
            }
        }
    }

    func delete(_ id: VehicleID) async throws {
        try state.withLock { s in
            if let error = s.error { throw error }
            s.vehicles.removeAll { $0.id == id }
            s.deleted.append(id)
        }
    }
}
