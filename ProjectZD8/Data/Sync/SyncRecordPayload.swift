/// 1件の同期レコードの内容です。CloudKitのレコードとローカル行の間の中立な表現です。
///
/// セッションの `rawAvailability` と各行の `deletedAt` は端末ローカルの値で、レコードには含めません。
nonisolated enum SyncRecordPayload: Codable, Equatable, Sendable {
    case vehicle(SyncVehicleRow)
    case maintenanceRecord(SyncMaintenanceRow)
    case photo(SyncPhotoRow)
    case driveSession(SyncSessionRow)

    /// レコードの種類です。
    var recordType: SyncRecordType {
        switch self {
        case .vehicle: .vehicle
        case .maintenanceRecord: .maintenanceRecord
        case .photo: .photo
        case .driveSession: .driveSession
        }
    }

    /// レコード名(行のUUID文字列)です。
    var recordName: String {
        switch self {
        case .vehicle(let row): row.id
        case .maintenanceRecord(let row): row.id
        case .photo(let row): row.id
        case .driveSession(let row): row.id
        }
    }

    /// 所属する車両のIDです。車両自身は `nil` です。
    var parentVehicleID: String? {
        switch self {
        case .vehicle: nil
        case .maintenanceRecord(let row): row.vehicleID
        case .photo(let row): row.vehicleID
        case .driveSession(let row): row.vehicleID
        }
    }

    /// 最終更新日時(エポックミリ秒)です。競合解決に使います。
    var modifiedAt: Int64 {
        switch self {
        case .vehicle(let row): row.modifiedAt
        case .maintenanceRecord(let row): row.modifiedAt
        case .photo(let row): row.modifiedAt
        case .driveSession(let row): row.modifiedAt
        }
    }
}
