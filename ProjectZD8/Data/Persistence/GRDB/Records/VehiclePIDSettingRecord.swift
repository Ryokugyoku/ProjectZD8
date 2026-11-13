import Foundation
import GRDB

/// `vehicle_pid_settings` テーブルの1行です。
nonisolated struct VehiclePIDSettingRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "vehicle_pid_settings"

    var vehicleID: String
    var service: Int
    var pid: Int
    var isSupported: Bool
    var isCollectionEnabled: Bool
    var discoveredAt: Int64

    /// 責務: PID設定エンティティから行を生成します。
    init(_ setting: VehiclePIDSetting) {
        vehicleID = setting.vehicleID.rowID
        service = Int(setting.request.service)
        pid = Int(setting.request.pid)
        isSupported = setting.isSupported
        isCollectionEnabled = setting.isCollectionEnabled
        discoveredAt = setting.discoveredAt.epochMilliseconds
    }

    /// 責務: 行をPID設定エンティティへ変換します。範囲外の値は `StoreError.ioFailure` を投げます。
    func entity() throws -> VehiclePIDSetting {
        guard let service = UInt8(exactly: service), let pid = UInt8(exactly: pid) else { throw StoreError.ioFailure }
        return VehiclePIDSetting(
            vehicleID: try VehicleID(rowID: vehicleID),
            request: OBDPIDRequest(service: service, pid: pid),
            isSupported: isSupported,
            isCollectionEnabled: isCollectionEnabled,
            discoveredAt: Date(epochMilliseconds: discoveredAt)
        )
    }
}
