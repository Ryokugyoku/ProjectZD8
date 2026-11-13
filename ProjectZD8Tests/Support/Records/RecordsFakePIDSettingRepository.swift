import Foundation
import Synchronization
@testable import ProjectZD8

/// メモリ上のテスト用 `VehiclePIDSettingRepository` です。
final class RecordsFakePIDSettingRepository: VehiclePIDSettingRepository, Sendable {
    private let state: Mutex<State>

    private struct State {
        var settings: [VehiclePIDSetting]
        var error: StoreError?
    }

    init(settings: [VehiclePIDSetting] = []) {
        state = Mutex(State(settings: settings))
    }

    var stored: [VehiclePIDSetting] { state.withLock { $0.settings } }
    func setError(_ error: StoreError?) { state.withLock { $0.error = error } }

    func settings(for vehicleID: VehicleID) async throws -> [VehiclePIDSetting] {
        try state.withLock { s in
            if let error = s.error { throw error }
            return s.settings.filter { $0.vehicleID == vehicleID }
        }
    }

    func mergeDiscovered(_ supported: Set<OBDPIDRequest>, for vehicleID: VehicleID, at date: Date) async throws {}

    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) async throws {
        try state.withLock { s in
            if let error = s.error { throw error }
            guard let index = s.settings.firstIndex(where: { $0.vehicleID == vehicleID && $0.request == request }) else {
                throw StoreError.notFound
            }
            s.settings[index].isCollectionEnabled = isEnabled
        }
    }
}
