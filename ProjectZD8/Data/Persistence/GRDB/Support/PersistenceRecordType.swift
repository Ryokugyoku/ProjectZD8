/// `sync_records.recordType` に保存するCloudKitレコード種別名です。
nonisolated enum PersistenceRecordType {
    /// 車両です。
    static let vehicle = "RTVehicle"
    /// 整備記録です。
    static let maintenanceRecord = "RTMaintenanceRecord"
    /// 写真です。
    static let photo = "RTPhoto"
    /// 走行セッションです。
    static let driveSession = "RTDriveSession"
}
