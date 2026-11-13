import GRDB
import XCTest
@testable import ProjectZD8

/// 未送信の変更の導出と、送信結果の書き戻しを確認します。
final class SyncLocalStoreTests: XCTestCase {
    private var database: AppDatabase!
    private var photos: PhotoFileStore!
    private var store: SyncLocalStore!

    override func setUpWithError() throws {
        database = try AppDatabaseTesting.makeDatabase()
        photos = SyncTestFixtures.photoStore()
        store = SyncLocalStore(database: database, photoFiles: photos)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: photos.directory)
    }

    /// 責務: 新しい行は保存待ちになり、車両が先に並ぶことを確認します。
    func testNewRowsArePendingSavesWithVehiclesFirst() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let maintenance = SyncTestFixtures.maintenance(vehicleID: vehicle.id)
        let photo = SyncTestFixtures.photo(vehicleID: vehicle.id)
        let session = SyncTestFixtures.session(vehicleID: vehicle.id, archiveDigest: "d")
        try database.writer.write { db in
            try vehicle.insert(db)
            try maintenance.insert(db)
            try photo.insert(db)
            try session.insert(db)
        }
        let pending = try store.pendingChanges()
        XCTAssertEqual(pending, [
            SyncPendingChange(recordType: .vehicle, recordName: vehicle.id, kind: .save),
            SyncPendingChange(recordType: .photo, recordName: photo.id, kind: .save),
            SyncPendingChange(recordType: .maintenanceRecord, recordName: maintenance.id, kind: .save),
            SyncPendingChange(recordType: .driveSession, recordName: session.id, kind: .save),
        ])
    }

    /// 責務: 記録中とデモのセッションは同期しないことを確認します。
    func testRecordingAndDemoSessionsAreNotPending() throws {
        let vehicle = SyncTestFixtures.vehicle()
        try database.writer.write { db in
            try vehicle.insert(db)
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: vehicle.id, syncedModifiedAt: vehicle.modifiedAt)
            try SyncTestFixtures.session(vehicleID: vehicle.id, ended: false).insert(db)
            try SyncTestFixtures.session(vehicleID: vehicle.id, isDemo: true).insert(db)
        }
        XCTAssertEqual(try store.pendingChanges(), [])
    }

    /// 責務: 保存成功で送信済みになり、その後の更新で再び保存待ちになることを確認します。
    func testMarkSavedClearsPendingUntilNextModification() throws {
        let vehicle = SyncTestFixtures.vehicle(modifiedAt: 1_000)
        try database.writer.write { db in try vehicle.insert(db) }
        XCTAssertTrue(try store.markSaved(recordType: .vehicle, recordName: vehicle.id, systemFields: Data([9]), sentModifiedAt: 1_000))
        XCTAssertEqual(try store.pendingChanges(), [])

        try database.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET name = 'new', modifiedAt = 2000 WHERE id = ?", arguments: [vehicle.id])
        }
        XCTAssertEqual(try store.pendingChanges(), [SyncPendingChange(recordType: .vehicle, recordName: vehicle.id, kind: .save)])
        let outgoing = try XCTUnwrap(store.outgoingRecord(recordType: .vehicle, recordName: vehicle.id))
        XCTAssertEqual(outgoing.systemFields, Data([9]))
    }

    /// 責務: 送信中に更新された行は、古い版の保存成功後も保存待ちのままであることを確認します。
    func testMarkSavedWithOlderVersionKeepsRowPending() throws {
        let vehicle = SyncTestFixtures.vehicle(modifiedAt: 2_000)
        try database.writer.write { db in try vehicle.insert(db) }
        try store.markSaved(recordType: .vehicle, recordName: vehicle.id, systemFields: Data([1]), sentModifiedAt: 1_000)
        XCTAssertEqual(try store.pendingChanges().map(\.recordName), [vehicle.id])
    }

    /// 責務: ローカル行が無い保存成功は `false` を返すことを確認します。
    func testMarkSavedForMissingRowReturnsFalse() throws {
        XCTAssertFalse(try store.markSaved(recordType: .vehicle, recordName: SyncTestFixtures.newID(), systemFields: Data(), sentModifiedAt: 1))
    }

    /// 責務: 墓標行は子から先に削除待ちとして並び、削除完了で物理削除されることを確認します。
    func testTombstonesArePendingDeletionsAndConfirmedDeletionRemovesRows() throws {
        let vehicle = SyncTestFixtures.vehicle(deletedAt: 5_000)
        let maintenance = SyncTestFixtures.maintenance(vehicleID: vehicle.id, deletedAt: 5_000)
        try database.writer.write { db in
            try vehicle.insert(db)
            try maintenance.insert(db)
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: vehicle.id, syncedModifiedAt: 1_000)
            try SyncTestFixtures.markSynced(db, type: .maintenanceRecord, id: maintenance.id, syncedModifiedAt: 1_000)
        }
        XCTAssertEqual(try store.pendingChanges(), [
            SyncPendingChange(recordType: .maintenanceRecord, recordName: maintenance.id, kind: .delete),
            SyncPendingChange(recordType: .vehicle, recordName: vehicle.id, kind: .delete),
        ])
        XCTAssertNil(try store.outgoingRecord(recordType: .vehicle, recordName: vehicle.id))

        try store.markDeletionConfirmed(recordType: .maintenanceRecord, recordName: maintenance.id)
        try store.markDeletionConfirmed(recordType: .vehicle, recordName: vehicle.id)
        try database.writer.read { db in
            XCTAssertEqual(try SyncVehicleRow.fetchCount(db), 0)
            XCTAssertEqual(try SyncMaintenanceRow.fetchCount(db), 0)
            XCTAssertEqual(try SyncRecordMetadataRow.fetchCount(db), 0)
        }
    }

    /// 責務: Rawがローカルのセッションは、アーカイブの保存成功(検証値の記録)まで属性レコードを送らないことを確認します。
    func testSessionMetadataWaitsUntilArchiveUploaded() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: vehicle.id, sampleCount: 2, modifiedAt: 1_000)
        let demo = SyncTestFixtures.session(vehicleID: vehicle.id, isDemo: true)
        let recording = SyncTestFixtures.session(vehicleID: vehicle.id, ended: false)
        let cloudOnly = SyncTestFixtures.session(vehicleID: vehicle.id, rawAvailability: .cloudOnly, archiveDigest: "c")
        try database.writer.write { db in
            try vehicle.insert(db)
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: vehicle.id, syncedModifiedAt: vehicle.modifiedAt)
            for row in [session, demo, recording, cloudOnly] { try row.insert(db) }
            try SyncTestFixtures.markSynced(db, type: .driveSession, id: cloudOnly.id, syncedModifiedAt: cloudOnly.modifiedAt)
        }
        XCTAssertEqual(try store.pendingChanges(), [])
        XCTAssertNil(try store.outgoingRecord(recordType: .driveSession, recordName: session.id))
        XCTAssertEqual(try store.pendingArchiveUploads(), [session.id])

        try store.markArchiveUploaded(sessionID: session.id, vehicleID: vehicle.id, digest: "abc")

        XCTAssertEqual(try store.pendingArchiveUploads(), [])
        XCTAssertEqual(try store.pendingChanges(), [SyncPendingChange(recordType: .driveSession, recordName: session.id, kind: .save)])
        let outgoing = try XCTUnwrap(store.outgoingRecord(recordType: .driveSession, recordName: session.id))
        guard case .driveSession(let row) = outgoing.payload else { return XCTFail("セッションのはずです") }
        XCTAssertEqual(row.archiveDigest, "abc")
        XCTAssertEqual(row.modifiedAt, 1_000)
        XCTAssertEqual(try SyncArchiveIndex(database: database).entries(), [SyncArchiveIndex.Entry(sessionID: session.id, vehicleID: vehicle.id)])
    }

    /// 責務: セッションと車両の削除完了でアーカイブが削除待ちへ移ることを確認します。
    func testConfirmedDeletionsQueueArchiveDeletion() throws {
        let vehicle = SyncTestFixtures.vehicle(deletedAt: 9)
        let other = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: other.id, archiveDigest: "a", deletedAt: 9)
        try database.writer.write { db in
            try vehicle.insert(db)
            try other.insert(db)
            try session.insert(db)
            try SyncArchiveIndex.record(db, sessionID: session.id, vehicleID: other.id)
            try SyncArchiveIndex.record(db, sessionID: "gone-1", vehicleID: vehicle.id)
            try SyncArchiveIndex.record(db, sessionID: "gone-2", vehicleID: vehicle.id)
        }
        try store.markDeletionConfirmed(recordType: .driveSession, recordName: session.id)
        try store.markDeletionConfirmed(recordType: .vehicle, recordName: vehicle.id)
        let index = SyncArchiveIndex(database: database)
        XCTAssertEqual(try index.entries(), [])
        XCTAssertEqual(Set(try index.queuedDeletions().map(\.sessionID)), [session.id, "gone-1", "gone-2"])
    }

    /// 責務: 写真の送信材料に画像ファイルのURLが付くことを確認します。
    func testPhotoOutgoingRecordReferencesImageFile() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let photo = SyncTestFixtures.photo(vehicleID: vehicle.id)
        try database.writer.write { db in
            try vehicle.insert(db)
            try photo.insert(db)
        }
        let photoID = PhotoID(rawValue: try XCTUnwrap(UUID(uuidString: photo.id)))
        XCTAssertNil(try store.outgoingRecord(recordType: .photo, recordName: photo.id)?.photoFileURL)
        try photos.write(Data([1, 2, 3, 4]), for: photoID)
        XCTAssertEqual(try store.outgoingRecord(recordType: .photo, recordName: photo.id)?.photoFileURL, photos.url(for: photoID))
    }

    /// 責務: システムフィールドの差し替えが同期済み時点を保つことを確認します。
    func testReplaceSystemFieldsKeepsSyncedModifiedAt() throws {
        let vehicle = SyncTestFixtures.vehicle()
        try database.writer.write { db in
            try vehicle.insert(db)
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: vehicle.id, syncedModifiedAt: 1_000)
        }
        try store.replaceSystemFields(recordType: .vehicle, recordName: vehicle.id, systemFields: nil)
        let metadata = try database.writer.read { db in
            try SyncRecordMetadataRow.fetchOne(db, key: ["recordType": SyncRecordType.vehicle.rawValue, "recordID": vehicle.id])
        }
        XCTAssertNil(metadata?.systemFields)
        XCTAssertEqual(metadata?.syncedModifiedAt, 1_000)
    }

    /// 責務: レコード名から種類を引けることを確認します(同期管理行が無い墓標行も含む)。
    func testRecordTypeLookup() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: vehicle.id)
        try database.writer.write { db in
            try vehicle.insert(db)
            try session.insert(db)
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: vehicle.id, syncedModifiedAt: 1)
        }
        XCTAssertEqual(try store.recordType(forRecordName: vehicle.id), .vehicle)
        XCTAssertEqual(try store.recordType(forRecordName: session.id), .driveSession)
        XCTAssertNil(try store.recordType(forRecordName: SyncTestFixtures.newID()))
    }

    /// 責務: 送り直しの準備で、墓標行・同期管理行・保留が消え、ローカルRawの検証値が消えることを確認します。
    func testResetForReuploadMakesEverythingPending() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let deleted = SyncTestFixtures.vehicle(deletedAt: 9)
        let localSession = SyncTestFixtures.session(vehicleID: vehicle.id, archiveDigest: "a")
        let cloudSession = SyncTestFixtures.session(vehicleID: vehicle.id, rawAvailability: .cloudOnly, archiveDigest: "b")
        try database.writer.write { db in
            try vehicle.insert(db)
            try deleted.insert(db)
            try localSession.insert(db)
            try cloudSession.insert(db)
            for id in [vehicle.id, deleted.id] { try SyncTestFixtures.markSynced(db, type: .vehicle, id: id, syncedModifiedAt: 1_000) }
            for id in [localSession.id, cloudSession.id] { try SyncTestFixtures.markSynced(db, type: .driveSession, id: id, syncedModifiedAt: 1_000) }
            try db.execute(sql: "INSERT INTO sync_state (key, value) VALUES ('parked.RTPhoto.x', x'00'), ('engine.state', x'01')")
            try SyncArchiveIndex.record(db, sessionID: cloudSession.id, vehicleID: vehicle.id)
        }
        try store.resetForReupload()
        try database.writer.read { db in
            XCTAssertEqual(try SyncRecordMetadataRow.fetchCount(db), 0)
            XCTAssertEqual(try SyncVehicleRow.fetchCount(db), 1)
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT key FROM sync_state ORDER BY key"), ["archive.index.\(cloudSession.id)", "engine.state"])
            XCTAssertNil(try SyncSessionRow.fetchOne(db, key: localSession.id)?.archiveDigest)
            XCTAssertEqual(try SyncSessionRow.fetchOne(db, key: cloudSession.id)?.archiveDigest, "b")
        }
        XCTAssertEqual(Set(try store.pendingChanges().map(\.recordName)), [vehicle.id, cloudSession.id])
        XCTAssertEqual(try store.pendingArchiveUploads(), [localSession.id])
    }
}
