import Foundation
import GRDB

/// 車両別対応PIDと収集選択をGRDBへ保存します。
final class GRDBVehiclePIDCapabilityRepository: VehiclePIDCapabilityRepository, @unchecked Sendable {
    /// SQLiteの直列化された読書き境界です。
    private let databaseQueue: DatabaseQueue

    /// 指定DB Queueを現行PIDスキーマへ移行して生成します。
    ///
    /// 責務: 1件のSQLite接続を車両別対応PID保存に利用可能な状態へします。
    /// - Parameter databaseQueue: 車両別PID設定を保存するDB Queue。
    /// - Throws: Migrationに失敗した場合のGRDBエラー。
    init(databaseQueue: DatabaseQueue) throws {
        self.databaseQueue = databaseQueue
        try OBDPIDDatabaseMigrator.migrator.migrate(databaseQueue)
    }

    /// Application Support内の製品DBを開きます。
    ///
    /// 責務: 製品DBの車両別対応PID Repositoryを生成します。
    /// - Returns: Migration済みRepository。
    /// - Throws: 保存先作成、DB接続、Migrationに失敗した場合のエラー。
    static func openApplicationRepository() throws -> GRDBVehiclePIDCapabilityRepository {
        let fileManager = FileManager.default
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appending(path: "ProjectZD8", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return try GRDBVehiclePIDCapabilityRepository(
            databaseQueue: DatabaseQueue(path: directory.appending(path: "projectzd8.sqlite").path)
        )
    }

    /// 指定車両で確認済みの対応PIDを取得します。
    ///
    /// 責務: 1件の車両IDに属する対応PIDをService/PID順で復元します。
    /// - Parameter vehicleID: 照会する車両ID。
    /// - Returns: 永続化済み対応PID設定。
    /// - Throws: SQLite読込または不正レコードの場合のエラー。
    func capabilities(for vehicleID: VehicleID) throws -> [VehiclePIDCapability] {
        try databaseQueue.read { database in
            let records = try VehiclePIDCapabilityRecord
                .filter(Column("vehicleID") == vehicleID.rawValue.uuidString.lowercased())
                .order(Column("service"), Column("pid"))
                .fetchAll(database)
            return try records.map {
                guard let capability = $0.makeDomainCapability() else {
                    throw DatabaseError(message: "Vehicle PID capability contains an invalid identifier")
                }
                return capability
            }
        }
    }

    /// 未収集車両へ対応PIDを全件収集有効で登録します。
    ///
    /// 責務: 0件の車両スコープへ探索結果を原子的に初期登録します。
    /// - Parameters:
    ///   - capabilities: 登録する対応PID。
    ///   - vehicleID: 登録先の車両ID。
    /// - Throws: 既存レコードまたはSQLite書込失敗の場合のエラー。
    func insertInitial(_ capabilities: [VehiclePIDCapability], for vehicleID: VehicleID) throws {
        try databaseQueue.write { database in
            let count = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM vehicle_pid_capabilities WHERE vehicleID = ?",
                arguments: [vehicleID.rawValue.uuidString.lowercased()]
            ) ?? 0
            guard count == 0 else { throw DatabaseError(message: "Vehicle PID capabilities already exist") }
            for capability in capabilities {
                guard capability.id.vehicleID == vehicleID, capability.isCollectionEnabled else {
                    throw DatabaseError(message: "Initial vehicle PID capabilities must match the vehicle and be enabled")
                }
                try VehiclePIDCapabilityRecord(capability: capability).insert(database)
            }
        }
    }

    /// 1件の対応PIDの収集選択を更新します。
    ///
    /// 責務: 指定車両の指定PIDだけの収集有効状態を変更します。
    /// - Parameters:
    ///   - isEnabled: 新しい収集有効状態。
    ///   - request: 更新するService/PID。
    ///   - vehicleID: 更新対象の車両ID。
    /// - Throws: 対象不在またはSQLite書込失敗の場合のエラー。
    func setCollectionEnabled(_ isEnabled: Bool, for request: OBDPIDRequest, vehicleID: VehicleID) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: "UPDATE vehicle_pid_capabilities SET isCollectionEnabled = ? WHERE vehicleID = ? AND service = ? AND pid = ?",
                arguments: [isEnabled, vehicleID.rawValue.uuidString.lowercased(), Int(request.service), Int(request.pid)]
            )
            guard database.changesCount == 1 else { throw DatabaseError(message: "Vehicle PID capability was not found") }
        }
    }
}
