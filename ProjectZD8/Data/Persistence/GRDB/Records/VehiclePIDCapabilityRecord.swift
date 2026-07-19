import Foundation
import GRDB

/// `vehicle_pid_capabilities` と車両別対応PID設定を相互変換します。
struct VehiclePIDCapabilityRecord: Codable, FetchableRecord, PersistableRecord {
    /// 永続化先テーブル名です。
    static let databaseTableName = "vehicle_pid_capabilities"
    /// 車両ID文字列です。
    let vehicleID: String
    /// OBD Service番号です。
    let service: Int
    /// Service内PID番号です。
    let pid: Int
    /// 継続収集の有効状態です。
    let isCollectionEnabled: Bool
    /// 対応確認日時です。
    let discoveredAt: Date

    /// Domain設定を永続化列へ変換します。
    ///
    /// 責務: 1件の車両別対応PID設定をSQLite列型へ写像します。
    /// - Parameter capability: 永続化する対応PID設定。
    init(capability: VehiclePIDCapability) {
        vehicleID = capability.id.vehicleID.rawValue.uuidString.lowercased()
        service = Int(capability.id.request.service)
        pid = Int(capability.id.request.pid)
        isCollectionEnabled = capability.isCollectionEnabled
        discoveredAt = capability.discoveredAt
    }

    /// 永続化列をDomain設定へ変換します。
    ///
    /// 責務: 検証済みSQLite列を車両別対応PID設定へ写像します。
    /// - Returns: 識別子が有効な場合のDomain設定。
    func makeDomainCapability() -> VehiclePIDCapability? {
        guard let uuid = UUID(uuidString: vehicleID),
              let service = UInt8(exactly: service),
              let pid = UInt8(exactly: pid) else { return nil }
        return VehiclePIDCapability(
            vehicleID: VehicleID(rawValue: uuid),
            request: OBDPIDRequest(service: service, pid: pid),
            isCollectionEnabled: isCollectionEnabled,
            discoveredAt: discoveredAt
        )
    }
}
