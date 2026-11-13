import GRDB
import XCTest
@testable import ProjectZD8

/// セッションのRawの取り出しと復元を確認します。
final class SyncSessionArchiveStoreTests: XCTestCase {
    /// 責務: 終了済みのローカルセッションから全Rawのアーカイブを作れることを確認します。
    func testMakeArchiveCollectsSessionPIDsAndSamples() throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let vehicle = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: vehicle.id, sampleCount: 3)
        try database.writer.write { db in
            try vehicle.insert(db)
            try session.insert(db)
            try SyncTestFixtures.insertRaw(db, sessionID: session.id, count: 3)
        }
        let archive = try XCTUnwrap(SyncSessionArchiveStore(database: database).makeArchive(sessionID: session.id))
        XCTAssertEqual(archive.session.id.rawValue.uuidString.lowercased(), session.id)
        XCTAssertEqual(archive.pids.count, 1)
        XCTAssertEqual(archive.pids.first?.header, nil)
        XCTAssertEqual(archive.samples.map(\.sequence), [0, 1, 2])
        XCTAssertNil(archive.session.archiveDigest)
    }

    /// 責務: 記録中・デモ・Rawが端末に無いセッションはアーカイブにしないことを確認します。
    func testMakeArchiveSkipsIneligibleSessions() throws {
        let database = try AppDatabaseTesting.makeDatabase()
        let vehicle = SyncTestFixtures.vehicle()
        let recording = SyncTestFixtures.session(vehicleID: vehicle.id, ended: false)
        let demo = SyncTestFixtures.session(vehicleID: vehicle.id, isDemo: true)
        let cloudOnly = SyncTestFixtures.session(vehicleID: vehicle.id, rawAvailability: .cloudOnly, archiveDigest: "x")
        try database.writer.write { db in
            try vehicle.insert(db)
            for row in [recording, demo, cloudOnly] { try row.insert(db) }
        }
        let store = SyncSessionArchiveStore(database: database)
        XCTAssertNil(try store.makeArchive(sessionID: recording.id))
        XCTAssertNil(try store.makeArchive(sessionID: demo.id))
        XCTAssertNil(try store.makeArchive(sessionID: cloudOnly.id))
    }

    /// 責務: 復元がPIDとサンプルを書き込み、Rawをローカル扱いにし、更新日時を変えないことを確認します。
    func testRestoreWritesRawAndMarksLocalWithoutTouchingModifiedAt() throws {
        let source = try AppDatabaseTesting.makeDatabase()
        let vehicle = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: vehicle.id, sampleCount: 5)
        try source.writer.write { db in
            try vehicle.insert(db)
            try session.insert(db)
            try SyncTestFixtures.insertRaw(db, sessionID: session.id, count: 5)
        }
        let archive = try XCTUnwrap(SyncSessionArchiveStore(database: source).makeArchive(sessionID: session.id))

        let target = try AppDatabaseTesting.makeDatabase()
        var cloudOnly = session
        cloudOnly.rawAvailability = RawAvailability.cloudOnly.rawValue
        cloudOnly.archiveDigest = "digest"
        try target.writer.write { db in
            try vehicle.insert(db)
            try cloudOnly.insert(db)
        }
        let store = SyncSessionArchiveStore(database: target)
        XCTAssertEqual(try store.restoreTarget(sessionID: session.id)?.rawAvailability, .cloudOnly)
        try store.restore(archive)

        try target.writer.read { db in
            let restored = try XCTUnwrap(SyncSessionRow.fetchOne(db, key: session.id))
            XCTAssertEqual(restored.rawAvailability, RawAvailability.local.rawValue)
            XCTAssertEqual(restored.modifiedAt, session.modifiedAt)
            XCTAssertEqual(restored.archiveDigest, "digest")
            XCTAssertEqual(try SyncSessionSampleRow.fetchCount(db), 5)
            XCTAssertEqual(try SyncSessionPIDRow.fetchCount(db), 1)
        }
    }

    /// 責務: 対象のセッション行が無ければ復元が失敗することを確認します。
    func testRestoreWithoutSessionRowThrowsNotFound() throws {
        let source = try AppDatabaseTesting.makeDatabase()
        let vehicle = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: vehicle.id)
        try source.writer.write { db in
            try vehicle.insert(db)
            try session.insert(db)
        }
        let archive = try XCTUnwrap(SyncSessionArchiveStore(database: source).makeArchive(sessionID: session.id))
        let empty = try AppDatabaseTesting.makeDatabase()
        XCTAssertThrowsError(try SyncSessionArchiveStore(database: empty).restore(archive)) { error in
            XCTAssertEqual(error as? SyncLocalStoreError, .rowNotFound)
        }
    }
}
