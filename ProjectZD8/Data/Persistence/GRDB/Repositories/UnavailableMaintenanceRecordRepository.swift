/// GRDBを開けない場合に失敗を明示する整備記録境界です。
struct UnavailableMaintenanceRecordRepository: MaintenanceRecordRepository {
    /// 読込不能を返します。
    ///
    /// 責務: 整備記録の利用不能状態を読込失敗として保持します。
    /// - Parameter accountIdentifier: 読込を試みたアカウント識別子。
    /// - Returns: 正常値は返しません。
    /// - Throws: 常に `MaintenanceRepositoryError.unavailable`。
    func records(for accountIdentifier: String) async throws -> [MaintenanceRecord] {
        throw MaintenanceRepositoryError.unavailable
    }

    /// 保存不能を返します。
    ///
    /// 責務: 整備記録の利用不能状態を保存失敗として保持します。
    /// - Parameters:
    ///   - record: 保存を試みた整備記録。
    ///   - accountIdentifier: 保存を試みたアカウント識別子。
    /// - Throws: 常に `MaintenanceRepositoryError.unavailable`。
    func save(_ record: MaintenanceRecord, for accountIdentifier: String) async throws {
        throw MaintenanceRepositoryError.unavailable
    }

    /// 一括保存不能を返します。
    ///
    /// 責務: 整備集合の利用不能状態を一括保存失敗として保持します。
    /// - Parameters:
    ///   - records: 保存を試みた整備記録集合。
    ///   - accountIdentifier: 保存を試みたアカウント識別子。
    /// - Throws: 常に `MaintenanceRepositoryError.unavailable`。
    func replaceAll(_ records: [MaintenanceRecord], for accountIdentifier: String) async throws {
        throw MaintenanceRepositoryError.unavailable
    }
}
