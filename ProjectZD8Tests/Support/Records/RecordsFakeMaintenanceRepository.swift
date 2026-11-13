import Foundation
import Synchronization
@testable import ProjectZD8

/// メモリ上のテスト用 `MaintenanceRepository` です。
final class RecordsFakeMaintenanceRepository: MaintenanceRepository, Sendable {
    private let state: Mutex<State>

    private struct State {
        var records: [MaintenanceRecord]
        var error: StoreError?
        var saveError: StoreError?
    }

    init(records: [MaintenanceRecord] = []) {
        state = Mutex(State(records: records))
    }

    var stored: [MaintenanceRecord] { state.withLock { $0.records } }
    func setError(_ error: StoreError?) { state.withLock { $0.error = error } }
    func setSaveError(_ error: StoreError?) { state.withLock { $0.saveError = error } }
    func replace(_ records: [MaintenanceRecord]) { state.withLock { $0.records = records } }

    func records(for vehicleID: VehicleID) async throws -> [MaintenanceRecord] {
        try state.withLock { s in
            if let error = s.error { throw error }
            return s.records.filter { $0.vehicleID == vehicleID }.sorted { $0.performedAt > $1.performedAt }
        }
    }

    func save(_ record: MaintenanceRecord) async throws {
        try state.withLock { s in
            if let error = s.saveError ?? s.error { throw error }
            if let index = s.records.firstIndex(where: { $0.id == record.id }) {
                s.records[index] = record
            } else {
                s.records.append(record)
            }
        }
    }

    func delete(_ id: MaintenanceRecordID) async throws {
        try state.withLock { s in
            if let error = s.error { throw error }
            s.records.removeAll { $0.id == id }
        }
    }
}
