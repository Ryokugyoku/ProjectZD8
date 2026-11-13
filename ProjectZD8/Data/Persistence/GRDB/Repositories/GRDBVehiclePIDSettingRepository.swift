import Foundation
import GRDB

/// 車両別のPID対応状況と収集設定をGRDBで永続化します。
nonisolated struct GRDBVehiclePIDSettingRepository: VehiclePIDSettingRepository {
    private let database: AppDatabase

    /// 責務: 共有データベースを使うリポジトリを生成します。
    init(database: AppDatabase) {
        self.database = database
    }

    /// 責務: 車両の全PID設定をサービス・PID順で返します。
    func settings(for vehicleID: VehicleID) async throws -> [VehiclePIDSetting] {
        try await database.storeRead { db in
            try VehiclePIDSettingRecord
                .filter(Column("vehicleID") == vehicleID.rowID)
                .order(Column("service"), Column("pid"))
                .fetchAll(db)
                .map { try $0.entity() }
        }
    }

    /// 責務: 探索結果を反映します。指定PIDは対応済みにし、既存でそれ以外のPIDは非対応にします。収集設定は変えず、未登録PIDは収集有効で追加します。
    func mergeDiscovered(_ supported: Set<OBDPIDRequest>, for vehicleID: VehicleID, at date: Date) async throws {
        let rowID = vehicleID.rowID
        let discoveredAt = date.epochMilliseconds
        try await database.storeWrite { db in
            guard try VehicleRecord.filter(Column("id") == rowID && Column("deletedAt") == nil).fetchCount(db) == 1 else {
                throw StoreError.notFound
            }
            let existing = try VehiclePIDSettingRecord.filter(Column("vehicleID") == rowID).fetchAll(db)
            var known = Set<OBDPIDRequest>()
            for var record in existing {
                guard let service = UInt8(exactly: record.service), let pid = UInt8(exactly: record.pid) else { throw StoreError.ioFailure }
                let request = OBDPIDRequest(service: service, pid: pid)
                known.insert(request)
                record.isSupported = supported.contains(request)
                record.discoveredAt = discoveredAt
                try record.update(db)
            }
            for request in supported.subtracting(known) {
                try VehiclePIDSettingRecord(
                    VehiclePIDSetting(vehicleID: vehicleID, request: request, isSupported: true, isCollectionEnabled: true, discoveredAt: date)
                ).insert(db)
            }
        }
    }

    /// 責務: 1つのPIDの収集有効・無効を切り替えます。設定が無ければ `StoreError.notFound` を投げます。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) async throws {
        try await database.storeWrite { db in
            try db.execute(
                sql: "UPDATE vehicle_pid_settings SET isCollectionEnabled = ? WHERE vehicleID = ? AND service = ? AND pid = ?",
                arguments: [isEnabled, vehicleID.rowID, Int(request.service), Int(request.pid)]
            )
            guard db.changesCount == 1 else { throw StoreError.notFound }
        }
    }
}
