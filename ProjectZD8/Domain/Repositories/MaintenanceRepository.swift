/// 整備記録の永続化契約です。
nonisolated protocol MaintenanceRepository: Sendable {
    /// 責務: 車両の削除されていない整備記録を実施日の新しい順で返します。
    func records(for vehicleID: VehicleID) async throws -> [MaintenanceRecord]
    /// 責務: 整備記録を新規保存または上書きします。
    func save(_ record: MaintenanceRecord) async throws
    /// 責務: 整備記録を削除します。記録だけが参照していた写真も削除します。
    func delete(_ id: MaintenanceRecordID) async throws
}
