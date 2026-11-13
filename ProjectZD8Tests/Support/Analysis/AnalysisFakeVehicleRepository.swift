import Foundation
@testable import ProjectZD8

/// 分析テスト用の車両保管庫です。
actor AnalysisFakeVehicleRepository: VehicleRepository {
    private var stored: [VehicleID: Vehicle]

    /// 責務: 指定の車両で保管庫を生成します。
    init(_ vehicles: [Vehicle] = []) {
        stored = Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0) })
    }

    func vehicles() async throws -> [Vehicle] { stored.values.sorted { $0.name < $1.name } }
    func vehicle(_ id: VehicleID) async throws -> Vehicle? { stored[id] }
    func save(_ vehicle: Vehicle) async throws { stored[vehicle.id] = vehicle }
    func delete(_ id: VehicleID) async throws { stored[id] = nil }
}
