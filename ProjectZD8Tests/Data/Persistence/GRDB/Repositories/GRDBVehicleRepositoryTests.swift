import GRDB
import XCTest
@testable import ProjectZD8

/// `GRDBVehicleRepository` の契約と削除規則を検証します。
final class GRDBVehicleRepositoryTests: XCTestCase {
    private typealias Fixtures = PersistenceTestFixtures

    private func makeRepository(_ database: AppDatabase, clock: PersistenceTestClock = PersistenceTestClock()) -> GRDBVehicleRepository {
        GRDBVehicleRepository(database: database, photoFiles: Fixtures.temporaryPhotoStore(self), now: { clock.now })
    }

    /// 責務: 保存した車両を全項目欠落なく読み戻せることを確認します。
    func testSaveRoundTripsAllFields() async throws {
        let repository = makeRepository(try AppDatabaseTesting.makeDatabase())
        let vehicle = Fixtures.vehicle(photoID: PhotoID())
        try await repository.save(vehicle)
        let loaded = try await repository.vehicle(vehicle.id)
        XCTAssertEqual(loaded, vehicle)
    }

    /// 責務: 同一IDの保存が上書きになり、名称順で返ることを確認します。
    func testSaveOverwritesAndListsByName() async throws {
        let repository = makeRepository(try AppDatabaseTesting.makeDatabase())
        var b = Fixtures.vehicle(name: "bravo")
        let a = Fixtures.vehicle(name: "Alpha")
        try await repository.save(b)
        try await repository.save(a)
        b.name = "Zulu"
        try await repository.save(b)
        let names = try await repository.vehicles().map(\.name)
        XCTAssertEqual(names, ["Alpha", "Zulu"])
    }

    /// 責務: 存在しない車両は `nil` を返すことを確認します。
    func testVehicleMissingReturnsNil() async throws {
        let repository = makeRepository(try AppDatabaseTesting.makeDatabase())
        let missing = try await repository.vehicle(VehicleID())
        XCTAssertNil(missing)
    }

    /// 責務: 未同期の車両が物理削除されることを確認します。
    func testDeleteUnsyncedVehicleIsPhysical() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let repository = makeRepository(database)
        let vehicle = Fixtures.vehicle()
        try await repository.save(vehicle)
        try await repository.delete(vehicle.id)
        XCTAssertEqual(try Fixtures.count(database, "vehicles"), 0)
    }

    /// 責務: 同期済みの車両が墓標化され、照会に現れないことを確認します。
    func testDeleteSyncedVehicleIsTombstoned() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let clock = PersistenceTestClock(Fixtures.date(100))
        let repository = makeRepository(database, clock: clock)
        let vehicle = Fixtures.vehicle()
        try await repository.save(vehicle)
        try Fixtures.markSynced(database, recordType: "RTVehicle", id: vehicle.id.rowID)
        try await repository.delete(vehicle.id)

        let row = try await database.writer.read { try VehicleRecord.fetchOne($0) }
        XCTAssertEqual(row?.deletedAt, Fixtures.date(100).epochMilliseconds)
        XCTAssertEqual(row?.modifiedAt, Fixtures.date(100).epochMilliseconds)
        let vehicles = try await repository.vehicles()
        XCTAssertTrue(vehicles.isEmpty)
        let loaded = try await repository.vehicle(vehicle.id)
        XCTAssertNil(loaded)
    }

    /// 責務: 存在しない車両の削除が `notFound` になることを確認します。
    func testDeleteMissingThrowsNotFound() async throws {
        let repository = makeRepository(try AppDatabaseTesting.makeDatabase())
        do {
            try await repository.delete(VehicleID())
            XCTFail("notFound を期待")
        } catch {
            XCTAssertEqual(error as? StoreError, .notFound)
        }
    }

    /// 責務: 車両削除が子データ・写真ファイル・子の同期管理行を即時に物理削除することを確認します(車両自身は墓標化)。
    func testDeleteCascadesChildrenImmediately() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let files = Fixtures.temporaryPhotoStore(self)
        let vehicles = GRDBVehicleRepository(database: database, photoFiles: files)
        let photos = GRDBPhotoRepository(database: database, files: files)
        let sessions = GRDBSessionRepository(database: database)
        let maintenance = GRDBMaintenanceRepository(database: database, photoFiles: files)
        let settings = GRDBVehiclePIDSettingRepository(database: database)

        let vehicle = Fixtures.vehicle()
        try await vehicles.save(vehicle)
        let photoID = try await photos.save(try Fixtures.imageData(width: 10, height: 10), for: vehicle.id)
        let record = Fixtures.maintenance(vehicleID: vehicle.id, photos: [photoID])
        try await maintenance.save(record)
        let session = Fixtures.session(vehicleID: vehicle.id)
        try await sessions.begin(session, pids: [Fixtures.sessionPID(ordinal: 0, pid: 12)])
        try await sessions.append([Fixtures.sample(0)], to: session.id)
        try await settings.mergeDiscovered([Fixtures.request(12)], for: vehicle.id, at: Fixtures.date())
        for (type, id) in [("RTVehicle", vehicle.id.rowID), ("RTPhoto", photoID.rowID), ("RTMaintenanceRecord", record.id.rowID), ("RTDriveSession", session.id.rowID)] {
            try Fixtures.markSynced(database, recordType: type, id: id)
        }

        try await vehicles.delete(vehicle.id)

        for table in ["sessions", "session_pids", "session_samples", "maintenance_records", "photos", "vehicle_pid_settings"] {
            XCTAssertEqual(try Fixtures.count(database, table), 0, table)
        }
        XCTAssertNil(try files.read(photoID))
        XCTAssertEqual(try Fixtures.count(database, "sync_records"), 1)
        XCTAssertEqual(try Fixtures.count(database, "sync_records", where: "recordType = 'RTVehicle'"), 1)
        XCTAssertEqual(try Fixtures.count(database, "vehicles", where: "deletedAt IS NOT NULL"), 1)
    }

    /// 責務: 他の車両のデータが削除に巻き込まれないことを確認します。
    func testDeleteLeavesOtherVehicles() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let repository = makeRepository(database)
        let sessions = GRDBSessionRepository(database: database)
        let a = Fixtures.vehicle(name: "a")
        let b = Fixtures.vehicle(name: "b")
        try await repository.save(a)
        try await repository.save(b)
        try await sessions.begin(Fixtures.session(vehicleID: b.id), pids: [])
        try await repository.delete(a.id)
        XCTAssertEqual(try Fixtures.count(database, "sessions"), 1)
        let remaining = try await repository.vehicles().map(\.id)
        XCTAssertEqual(remaining, [b.id])
    }
}
