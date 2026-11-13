import Foundation
@testable import ProjectZD8

/// メモリ上の `VehiclePIDSettingRepository` です。本番同様、既存行の収集設定は保ち、未登録は有効で追加します。
final class DriveFlowPIDSettingRepository: VehiclePIDSettingRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [VehiclePIDSetting]
    private var merged: [Set<OBDPIDRequest>] = []

    init(rows: [VehiclePIDSetting] = []) { self.rows = rows }

    /// `mergeDiscovered` に渡された対応PID集合を呼び出し順に返します。
    var mergedSets: [Set<OBDPIDRequest>] { lock.withLock { merged } }

    func settings(for vehicleID: VehicleID) async throws -> [VehiclePIDSetting] {
        lock.withLock { rows.filter { $0.vehicleID == vehicleID } }
    }

    func mergeDiscovered(_ supported: Set<OBDPIDRequest>, for vehicleID: VehicleID, at date: Date) async throws {
        lock.withLock {
            merged.append(supported)
            for request in supported where !rows.contains(where: { $0.vehicleID == vehicleID && $0.request == request }) {
                rows.append(VehiclePIDSetting(vehicleID: vehicleID, request: request, isSupported: true, discoveredAt: date))
            }
        }
    }

    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) async throws {
        lock.withLock {
            guard let index = rows.firstIndex(where: { $0.vehicleID == vehicleID && $0.request == request }) else { return }
            rows[index].isCollectionEnabled = isEnabled
        }
    }
}
