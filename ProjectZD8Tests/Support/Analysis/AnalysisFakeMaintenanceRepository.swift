import Foundation
@testable import ProjectZD8

/// 分析テスト用の整備記録保管庫です。
actor AnalysisFakeMaintenanceRepository: MaintenanceRepository {
    private var stored: [MaintenanceRecord]

    /// 責務: 指定の記録で保管庫を生成します。
    init(_ records: [MaintenanceRecord] = []) {
        stored = records
    }

    func records(for vehicleID: VehicleID) async throws -> [MaintenanceRecord] {
        stored.filter { $0.vehicleID == vehicleID }.sorted { $0.performedAt > $1.performedAt }
    }
    func save(_ record: MaintenanceRecord) async throws { stored.append(record) }
    func delete(_ id: MaintenanceRecordID) async throws { stored.removeAll { $0.id == id } }
}
