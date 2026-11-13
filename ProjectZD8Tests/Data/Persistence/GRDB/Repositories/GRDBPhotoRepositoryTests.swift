import GRDB
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ProjectZD8

/// `GRDBPhotoRepository` の保存・正規化・削除を検証します。
final class GRDBPhotoRepositoryTests: XCTestCase {
    private typealias Fixtures = PersistenceTestFixtures

    private func makeFixture(clock: PersistenceTestClock = PersistenceTestClock()) async throws -> (GRDBPhotoRepository, AppDatabase, PhotoFileStore, VehicleID) {
        let database = try AppDatabaseTesting.makeDatabase()
        let files = Fixtures.temporaryPhotoStore(self)
        let vehicle = Fixtures.vehicle()
        try await GRDBVehicleRepository(database: database, photoFiles: files).save(vehicle)
        return (GRDBPhotoRepository(database: database, files: files, now: { clock.now }), database, files, vehicle.id)
    }

    private func properties(of data: Data) throws -> (type: String?, width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (CGImageSourceGetType(source) as String?, props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    /// 責務: 大きな画像が長辺2048px以下のJPEGへ縮小され、縦横比が保たれることを確認します。
    func testSaveDownscalesLargeImageToJPEG() async throws {
        let (repository, database, _, vehicleID) = try await makeFixture()
        let id = try await repository.save(try Fixtures.imageData(width: 4000, height: 3000), for: vehicleID)
        let stored = try Fixtures.unwrapped(try await repository.imageData(for: id))
        let info = try properties(of: stored)
        XCTAssertEqual(info.type, UTType.jpeg.identifier)
        XCTAssertEqual(info.width, 2048)
        XCTAssertEqual(info.height, 1536)
        let byteCount = try await database.writer.read { try Int.fetchOne($0, sql: "SELECT byteCount FROM photos WHERE id = ?", arguments: [id.rowID]) }
        XCTAssertEqual(byteCount, stored.count)
    }

    /// 責務: 小さな画像は拡大されずJPEGへ変換されることを確認します。
    func testSaveKeepsSmallImageSize() async throws {
        let (repository, _, _, vehicleID) = try await makeFixture()
        let id = try await repository.save(try Fixtures.imageData(width: 64, height: 32), for: vehicleID)
        let info = try properties(of: try Fixtures.unwrapped(try await repository.imageData(for: id)))
        XCTAssertEqual(info.type, UTType.jpeg.identifier)
        XCTAssertEqual(info.width, 64)
        XCTAssertEqual(info.height, 32)
    }

    /// 責務: 画像として解釈できないデータが `ioFailure` になり、何も保存されないことを確認します。
    func testSaveRejectsNonImageData() async throws {
        let (repository, database, files, vehicleID) = try await makeFixture()
        do {
            _ = try await repository.save(Data("not an image".utf8), for: vehicleID)
            XCTFail("ioFailure を期待")
        } catch {
            XCTAssertEqual(error as? StoreError, .ioFailure)
        }
        XCTAssertEqual(try Fixtures.count(database, "photos"), 0)
        XCTAssertNil(try? FileManager.default.contentsOfDirectory(atPath: files.directory.path).first)
    }

    /// 責務: 存在しない車両への保存が `notFound` になりファイルが残らないことを確認します。
    func testSaveForMissingVehicleCleansUpFile() async throws {
        let (repository, _, files, _) = try await makeFixture()
        do {
            _ = try await repository.save(try Fixtures.imageData(width: 8, height: 8), for: VehicleID())
            XCTFail("notFound を期待")
        } catch {
            XCTAssertEqual(error as? StoreError, .notFound)
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).isEmpty)
    }

    /// 責務: 未同期の写真が行・ファイルとも削除され、`imageData` が `nil` を返すことを確認します。
    func testDeleteUnsyncedRemovesRowAndFile() async throws {
        let (repository, database, files, vehicleID) = try await makeFixture()
        let id = try await repository.save(try Fixtures.imageData(width: 8, height: 8), for: vehicleID)
        try await repository.delete(id)
        XCTAssertEqual(try Fixtures.count(database, "photos"), 0)
        XCTAssertNil(try files.read(id))
        let data = try await repository.imageData(for: id)
        XCTAssertNil(data)
    }

    /// 責務: 同期済みの写真が墓標化され、ファイルは消えて `imageData` が `nil` を返すことを確認します。
    func testDeleteSyncedTombstones() async throws {
        let clock = PersistenceTestClock(Fixtures.date(30))
        let (repository, database, files, vehicleID) = try await makeFixture(clock: clock)
        let id = try await repository.save(try Fixtures.imageData(width: 8, height: 8), for: vehicleID)
        try Fixtures.markSynced(database, recordType: "RTPhoto", id: id.rowID)
        clock.advance(by: 10)
        try await repository.delete(id)
        XCTAssertEqual(try Fixtures.count(database, "photos", where: "deletedAt = \(Fixtures.date(40).epochMilliseconds)"), 1)
        XCTAssertNil(try files.read(id))
        let data = try await repository.imageData(for: id)
        XCTAssertNil(data)
    }
}
