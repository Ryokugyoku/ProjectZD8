import XCTest
@testable import ProjectZD8

/// `GRDBMaintenanceRepository` の契約と写真の連動削除を検証します。
final class GRDBMaintenanceRepositoryTests: XCTestCase {
    private typealias Fixtures = PersistenceTestFixtures

    private struct Context {
        let database: AppDatabase
        let files: PhotoFileStore
        let maintenance: GRDBMaintenanceRepository
        let photos: GRDBPhotoRepository
        let vehicleID: VehicleID
    }

    private func makeContext(clock: PersistenceTestClock = PersistenceTestClock()) async throws -> Context {
        let database = try AppDatabaseTesting.makeDatabase()
        let files = Fixtures.temporaryPhotoStore(self)
        let vehicle = Fixtures.vehicle()
        try await GRDBVehicleRepository(database: database, photoFiles: files).save(vehicle)
        return Context(
            database: database, files: files,
            maintenance: GRDBMaintenanceRepository(database: database, photoFiles: files, now: { clock.now }),
            photos: GRDBPhotoRepository(database: database, files: files, now: { clock.now }),
            vehicleID: vehicle.id
        )
    }

    /// 責務: 作業項目・写真・締結グループを含む記録が欠落なく往復することを確認します。
    func testSaveRoundTripsDetail() async throws {
        let context = try await makeContext()
        let record = Fixtures.maintenance(vehicleID: context.vehicleID, photos: [PhotoID()])
        try await context.maintenance.save(record)
        let loaded = try await context.maintenance.records(for: context.vehicleID)
        XCTAssertEqual(loaded, [record])
    }

    /// 責務: 実施日の新しい順で返り、上書き保存が反映されることを確認します。
    func testRecordsAreOrderedByPerformedAtDescending() async throws {
        let context = try await makeContext()
        let old = Fixtures.maintenance(vehicleID: context.vehicleID, title: "old", performedAt: Fixtures.date(0))
        var new = Fixtures.maintenance(vehicleID: context.vehicleID, title: "new", performedAt: Fixtures.date(100))
        try await context.maintenance.save(old)
        try await context.maintenance.save(new)
        new.title = "renamed"
        try await context.maintenance.save(new)
        let titles = try await context.maintenance.records(for: context.vehicleID).map(\.title)
        XCTAssertEqual(titles, ["renamed", "old"])
    }

    /// 責務: 存在しない車両への保存が `notFound` になることを確認します。
    func testSaveForMissingVehicleThrowsNotFound() async throws {
        let context = try await makeContext()
        do {
            try await context.maintenance.save(Fixtures.maintenance(vehicleID: VehicleID()))
            XCTFail("notFound を期待")
        } catch {
            XCTAssertEqual(error as? StoreError, .notFound)
        }
    }

    /// 責務: 未同期の記録が物理削除され、記録だけが参照していた写真も消えることを確認します。
    func testDeleteUnsyncedRemovesRecordAndExclusivePhotos() async throws {
        let context = try await makeContext()
        let image = try Fixtures.imageData(width: 8, height: 8)
        let exclusive = try await context.photos.save(image, for: context.vehicleID)
        let shared = try await context.photos.save(image, for: context.vehicleID)
        let first = Fixtures.maintenance(vehicleID: context.vehicleID, title: "a", photos: [exclusive, shared])
        let second = Fixtures.maintenance(vehicleID: context.vehicleID, title: "b", photos: [shared])
        try await context.maintenance.save(first)
        try await context.maintenance.save(second)

        try await context.maintenance.delete(first.id)

        XCTAssertEqual(try Fixtures.count(context.database, "maintenance_records"), 1)
        XCTAssertNil(try context.files.read(exclusive))
        XCTAssertNotNil(try context.files.read(shared))
        XCTAssertEqual(try Fixtures.count(context.database, "photos"), 1)
    }

    /// 責務: 車両写真に使われている写真は記録削除で消えないことを確認します。
    func testDeleteKeepsPhotoUsedAsVehiclePhoto() async throws {
        let context = try await makeContext()
        let photo = try await context.photos.save(try Fixtures.imageData(width: 8, height: 8), for: context.vehicleID)
        var vehicle = Fixtures.vehicle(id: context.vehicleID)
        vehicle.photoID = photo
        try await GRDBVehicleRepository(database: context.database, photoFiles: context.files).save(vehicle)
        let record = Fixtures.maintenance(vehicleID: context.vehicleID, photos: [photo])
        try await context.maintenance.save(record)
        try await context.maintenance.delete(record.id)
        XCTAssertNotNil(try context.files.read(photo))
    }

    /// 責務: 同期済みの記録と専用写真が墓標化され、照会に現れないことを確認します。
    func testDeleteSyncedTombstonesRecordAndPhoto() async throws {
        let clock = PersistenceTestClock(Fixtures.date(50))
        let context = try await makeContext(clock: clock)
        let photo = try await context.photos.save(try Fixtures.imageData(width: 8, height: 8), for: context.vehicleID)
        let record = Fixtures.maintenance(vehicleID: context.vehicleID, photos: [photo])
        try await context.maintenance.save(record)
        try Fixtures.markSynced(context.database, recordType: "RTMaintenanceRecord", id: record.id.rowID)
        try Fixtures.markSynced(context.database, recordType: "RTPhoto", id: photo.rowID)

        try await context.maintenance.delete(record.id)

        let remaining = try await context.maintenance.records(for: context.vehicleID)
        XCTAssertTrue(remaining.isEmpty)
        let expected = Fixtures.date(50).epochMilliseconds
        XCTAssertEqual(try Fixtures.count(context.database, "maintenance_records", where: "deletedAt = \(expected) AND modifiedAt = \(expected)"), 1)
        XCTAssertEqual(try Fixtures.count(context.database, "photos", where: "deletedAt = \(expected)"), 1)
        XCTAssertNil(try context.files.read(photo))
    }

    /// 責務: 存在しない記録の削除が `notFound` になることを確認します。
    func testDeleteMissingThrowsNotFound() async throws {
        let context = try await makeContext()
        do {
            try await context.maintenance.delete(MaintenanceRecordID())
            XCTFail("notFound を期待")
        } catch {
            XCTAssertEqual(error as? StoreError, .notFound)
        }
    }
}
