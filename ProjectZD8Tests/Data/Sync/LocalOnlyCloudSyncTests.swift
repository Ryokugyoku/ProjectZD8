import GRDB
import XCTest
@testable import ProjectZD8

/// CloudKitに触れない同期を確認します。
final class LocalOnlyCloudSyncTests: XCTestCase {
    /// 責務: 利用不可を報告し、送受信と復元を型付きの失敗で拒否し、全削除はローカルだけを消すことを確認します。
    func testReportsUnavailableRejectsSyncAndErasesLocally() async throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let photos = SyncTestFixtures.photoStore()
        defer { try? FileManager.default.removeItem(at: photos.directory) }
        try await database.writer.write { db in try SyncTestFixtures.vehicle().insert(db) }
        let sync = LocalOnlyCloudSync(database: database, photoFiles: photos)
        await sync.start()

        var statuses: [CloudSyncStatus] = []
        for await status in sync.statusUpdates() { statuses.append(status) }
        XCTAssertEqual(statuses, [.unavailable(.temporarilyUnavailable)])

        do {
            try await sync.syncNow()
            XCTFail("同期は失敗するはずです")
        } catch {
            XCTAssertEqual(error as? CloudSyncFailure, .other)
        }
        do {
            try await sync.restoreSessionArchive(SessionID(), progress: { _ in })
            XCTFail("復元は失敗するはずです")
        } catch {
            XCTAssertEqual(error as? CloudSyncFailure, .other)
        }

        try await sync.eraseAllData()
        let count = try await database.writer.read { db in try SyncVehicleRow.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }
}
