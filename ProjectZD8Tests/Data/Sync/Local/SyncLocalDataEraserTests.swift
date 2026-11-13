import GRDB
import XCTest
@testable import ProjectZD8

/// この端末の全データ消去を確認します。
final class SyncLocalDataEraserTests: XCTestCase {
    /// 責務: 全テーブルの行・同期管理情報・写真ファイルが消えることを確認します。
    func testEraseAllRemovesRowsSyncStateAndPhotoFiles() throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let photos = SyncTestFixtures.photoStore()
        defer { try? FileManager.default.removeItem(at: photos.directory) }
        let vehicle = SyncTestFixtures.vehicle()
        let photo = SyncTestFixtures.photo(vehicleID: vehicle.id)
        let session = SyncTestFixtures.session(vehicleID: vehicle.id)
        try database.writer.write { db in
            try vehicle.insert(db)
            try photo.insert(db)
            try SyncTestFixtures.maintenance(vehicleID: vehicle.id).insert(db)
            try session.insert(db)
            try SyncTestFixtures.insertRaw(db, sessionID: session.id, count: 2)
            try db.execute(sql: "INSERT INTO vehicle_pid_settings (vehicleID, service, pid, isSupported, isCollectionEnabled, discoveredAt) VALUES (?, 1, 12, 1, 1, 0)", arguments: [vehicle.id])
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: vehicle.id, syncedModifiedAt: 1)
            try db.execute(sql: "INSERT INTO sync_state (key, value) VALUES ('engine.state', x'01')")
        }
        try photos.write(Data([1]), for: PhotoID(rawValue: try XCTUnwrap(UUID(uuidString: photo.id))))

        try SyncLocalDataEraser(database: database, photoFiles: photos).eraseAll()

        try database.writer.read { db in
            for table in ["vehicles", "photos", "vehicle_pid_settings", "maintenance_records", "sessions", "session_pids", "session_samples", "sync_records", "sync_state"] {
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)"), 0, table)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: photos.directory.path))
    }
}
