import GRDB
import XCTest
@testable import ProjectZD8

/// アーカイブの索引と削除待ちの列の管理を確認します。
final class SyncArchiveIndexTests: XCTestCase {
    private var database: AppDatabase!
    private var index: SyncArchiveIndex!

    override func setUpWithError() throws {
        database = try AppDatabaseTesting.makeDatabase()
        index = SyncArchiveIndex(database: database)
    }

    /// 責務: 登録・セッション単位の削除待ち・車両単位の削除待ちを確認します。
    func testRecordAndEnqueueBySessionAndVehicle() throws {
        try database.writer.write { db in
            try SyncArchiveIndex.record(db, sessionID: "s1", vehicleID: "v1")
            try SyncArchiveIndex.record(db, sessionID: "s2", vehicleID: "v1")
            try SyncArchiveIndex.record(db, sessionID: "s3", vehicleID: "v2")
        }
        XCTAssertEqual(try index.entries().map(\.sessionID), ["s1", "s2", "s3"])

        try database.writer.write { db in
            try SyncArchiveIndex.enqueueDeletion(db, sessionID: "s3")
            try SyncArchiveIndex.enqueueDeletion(db, sessionID: "unknown") // 索引に無いものは無視
        }
        XCTAssertEqual(try index.queuedDeletions(), [SyncArchiveIndex.Entry(sessionID: "s3", vehicleID: "v2")])

        try database.writer.write { db in try SyncArchiveIndex.enqueueDeletions(db, vehicleID: "v1") }
        XCTAssertEqual(try index.entries(), [])
        XCTAssertEqual(try index.queuedDeletions().map(\.sessionID), ["s1", "s2", "s3"])
    }

    /// 責務: 削除の一部だけが成功した時、失敗分が列に残って次回再試行され、全て済めば列が空になることを確認します。
    func testDrainKeepsFailuresQueuedForRetry() throws {
        try database.writer.write { db in
            for id in ["a", "b", "c"] {
                try SyncArchiveIndex.record(db, sessionID: id, vehicleID: "v")
                try SyncArchiveIndex.enqueueDeletion(db, sessionID: id)
            }
        }
        try index.deletionsCompleted(sessionIDs: ["a", "c"])
        XCTAssertEqual(try index.queuedDeletions().map(\.sessionID), ["b"])
        try index.deletionsCompleted(sessionIDs: ["b"])
        XCTAssertEqual(try index.queuedDeletions(), [])
    }

    /// 責務: セッション行が無い索引項目だけが照合で削除待ちへ移ることを確認します。
    func testReconcileQueuesArchivesWhoseSessionRowIsGone() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: vehicle.id, archiveDigest: "d")
        let tombstoned = SyncTestFixtures.session(vehicleID: vehicle.id, archiveDigest: "e", deletedAt: 5)
        try database.writer.write { db in
            try vehicle.insert(db)
            try session.insert(db)
            try tombstoned.insert(db)
            for id in [session.id, tombstoned.id, "physically-deleted"] {
                try SyncArchiveIndex.record(db, sessionID: id, vehicleID: vehicle.id)
            }
        }
        try index.reconcile()
        XCTAssertEqual(Set(try index.entries().map(\.sessionID)), [session.id, tombstoned.id])
        XCTAssertEqual(try index.queuedDeletions().map(\.sessionID), ["physically-deleted"])
    }

    /// 責務: 再登録(再アップロード)で同じセッションの削除待ちが取り消されることを確認します。
    func testRecordCancelsQueuedDeletion() throws {
        try database.writer.write { db in
            try SyncArchiveIndex.record(db, sessionID: "s", vehicleID: "v")
            try SyncArchiveIndex.enqueueDeletion(db, sessionID: "s")
            try SyncArchiveIndex.record(db, sessionID: "s", vehicleID: "v")
        }
        XCTAssertEqual(try index.queuedDeletions(), [])
        XCTAssertEqual(try index.entries().map(\.sessionID), ["s"])
    }
}
