import GRDB
import XCTest
@testable import ProjectZD8

/// リモート変更の適用(後勝ち・保留・削除)を確認します。
final class SyncRemoteChangeApplierTests: XCTestCase {
    private var database: AppDatabase!
    private var photos: PhotoFileStore!
    private var applier: SyncRemoteChangeApplier!
    private var store: SyncLocalStore!

    override func setUpWithError() throws {
        database = try AppDatabaseTesting.makeDatabase()
        photos = SyncTestFixtures.photoStore()
        applier = SyncRemoteChangeApplier(database: database, photoFiles: photos)
        store = SyncLocalStore(database: database, photoFiles: photos)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: photos.directory)
    }

    /// 責務: 新しいリモート車両がリモートの更新日時のまま書き込まれ、送り返されないことを確認します。
    func testNewRemoteVehicleIsAppliedAndNotEchoed() throws {
        let vehicle = SyncTestFixtures.vehicle(modifiedAt: 7_000)
        XCTAssertEqual(try applier.apply(.vehicle(vehicle), systemFields: Data([1])), .applied)
        let stored = try database.writer.read { db in try SyncVehicleRow.fetchOne(db, key: vehicle.id) }
        XCTAssertEqual(stored, vehicle)
        XCTAssertEqual(try store.pendingChanges(), [])
    }

    /// 責務: 親の車両より先に届いた子は保留され、車両の適用時に取り込まれることを確認します。
    func testChildBeforeVehicleIsParkedThenAppliedWithVehicle() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let maintenance = SyncTestFixtures.maintenance(vehicleID: vehicle.id)
        XCTAssertEqual(try applier.apply(.maintenanceRecord(maintenance), systemFields: Data([2])), .parked)
        XCTAssertEqual(try applier.parkedRecords().map(\.payload), [.maintenanceRecord(maintenance)])
        try database.writer.read { db in XCTAssertEqual(try SyncMaintenanceRow.fetchCount(db), 0) }

        XCTAssertEqual(try applier.apply(.vehicle(vehicle), systemFields: Data([1])), .applied)
        try database.writer.read { db in
            XCTAssertEqual(try SyncMaintenanceRow.fetchOne(db, key: maintenance.id), maintenance)
            let metadata = try SyncRecordMetadataRow.fetchOne(db, key: ["recordType": SyncRecordType.maintenanceRecord.rawValue, "recordID": maintenance.id])
            XCTAssertEqual(metadata?.systemFields, Data([2]))
        }
        XCTAssertEqual(try applier.parkedRecords(), [])
        XCTAssertEqual(try store.pendingChanges(), [])
    }

    /// 責務: ローカルに新しい未送信の変更があればローカルを残し、サーバーのシステムフィールドだけ取り込むことを確認します。
    func testNewerLocalPendingChangeWins() throws {
        let local = SyncTestFixtures.vehicle(name: "local", modifiedAt: 5_000)
        try database.writer.write { db in
            try local.insert(db)
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: local.id, syncedModifiedAt: 1_000, systemFields: Data([1]))
        }
        var remote = local
        remote.name = "remote"
        remote.modifiedAt = 4_000
        XCTAssertEqual(try applier.apply(.vehicle(remote), systemFields: Data([2])), .keptLocal)
        try database.writer.read { db in
            XCTAssertEqual(try SyncVehicleRow.fetchOne(db, key: local.id)?.name, "local")
        }
        let outgoing = try XCTUnwrap(store.outgoingRecord(recordType: .vehicle, recordName: local.id))
        XCTAssertEqual(outgoing.systemFields, Data([2]))
    }

    /// 責務: リモートの方が新しければ未送信のローカル変更より優先されることを確認します。
    func testNewerRemoteChangeWinsOverPendingLocal() throws {
        let local = SyncTestFixtures.vehicle(name: "local", modifiedAt: 5_000)
        try database.writer.write { db in
            try local.insert(db)
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: local.id, syncedModifiedAt: 1_000)
        }
        var remote = local
        remote.name = "remote"
        remote.modifiedAt = 6_000
        XCTAssertEqual(try applier.apply(.vehicle(remote), systemFields: Data([2])), .applied)
        try database.writer.read { db in
            XCTAssertEqual(try SyncVehicleRow.fetchOne(db, key: local.id)?.name, "remote")
        }
        XCTAssertEqual(try store.pendingChanges(), [])
    }

    /// 責務: 他端末のセッションはRawクラウドのみ・レコードの件数・サンプル無しで入ることを確認します。
    func testRemoteSessionIsInsertedCloudOnlyWithRecordCounters() throws {
        let vehicle = SyncTestFixtures.vehicle()
        try applier.apply(.vehicle(vehicle), systemFields: Data([1]))
        var remote = SyncTestFixtures.session(vehicleID: vehicle.id, archiveDigest: "d", sampleCount: 42)
        remote.rawAvailability = RawAvailability.local.rawValue
        XCTAssertEqual(try applier.apply(.driveSession(remote), systemFields: Data([3])), .applied)
        try database.writer.read { db in
            let stored = try XCTUnwrap(SyncSessionRow.fetchOne(db, key: remote.id))
            XCTAssertEqual(stored.rawAvailability, RawAvailability.cloudOnly.rawValue)
            XCTAssertEqual(stored.sampleCount, 42)
            XCTAssertEqual(stored.archiveDigest, "d")
            XCTAssertEqual(try SyncSessionSampleRow.fetchCount(db), 0)
        }
        XCTAssertEqual(try SyncArchiveIndex(database: database).entries(), [SyncArchiveIndex.Entry(sessionID: remote.id, vehicleID: vehicle.id)])
    }

    /// 責務: Rawがローカルにある既存セッションは、リモート更新後もRawの所在と件数を保つことを確認します。
    func testRemoteUpdateKeepsLocalRawAvailabilityAndCounters() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let local = SyncTestFixtures.session(vehicleID: vehicle.id, sampleCount: 3)
        try database.writer.write { db in
            try vehicle.insert(db)
            try local.insert(db)
            try SyncTestFixtures.markSynced(db, type: .vehicle, id: vehicle.id, syncedModifiedAt: vehicle.modifiedAt)
            try SyncTestFixtures.markSynced(db, type: .driveSession, id: local.id, syncedModifiedAt: local.modifiedAt)
        }
        var remote = local
        remote.odometerEndKilometers = 99
        remote.sampleCount = 0
        remote.rawAvailability = RawAvailability.cloudOnly.rawValue
        remote.modifiedAt = 9_000
        try applier.apply(.driveSession(remote), systemFields: Data([4]))
        let stored = try database.writer.read { db in try SyncSessionRow.fetchOne(db, key: local.id) }
        XCTAssertEqual(stored?.rawAvailability, RawAvailability.local.rawValue)
        XCTAssertEqual(stored?.sampleCount, 3)
        XCTAssertEqual(stored?.odometerEndKilometers, 99)
    }

    /// 責務: 写真の適用で画像ファイルが書き込まれ、車両削除の適用で子・ファイル・同期管理行が消えることを確認します。
    func testPhotoFileIsWrittenAndVehicleDeletionCascades() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let photo = SyncTestFixtures.photo(vehicleID: vehicle.id)
        let session = SyncTestFixtures.session(vehicleID: vehicle.id, archiveDigest: "d")
        try applier.apply(.vehicle(vehicle), systemFields: Data([1]))
        try applier.apply(.photo(photo), systemFields: Data([2]), photoImage: Data([0xFF, 0xD8]))
        try applier.apply(.driveSession(session), systemFields: Data([3]))
        let photoID = PhotoID(rawValue: try XCTUnwrap(UUID(uuidString: photo.id)))
        XCTAssertEqual(try photos.read(photoID), Data([0xFF, 0xD8]))

        try applier.applyDeletion(recordType: .vehicle, recordName: vehicle.id)
        XCTAssertNil(try photos.read(photoID))
        try database.writer.read { db in
            XCTAssertEqual(try SyncVehicleRow.fetchCount(db), 0)
            XCTAssertEqual(try SyncPhotoRow.fetchCount(db), 0)
            XCTAssertEqual(try SyncSessionRow.fetchCount(db), 0)
            XCTAssertEqual(try SyncRecordMetadataRow.fetchCount(db), 0)
        }
        let index = SyncArchiveIndex(database: database)
        XCTAssertEqual(try index.entries(), [])
        XCTAssertEqual(try index.queuedDeletions().map(\.sessionID), [session.id])
    }

    /// 責務: セッション削除の適用でそのアーカイブが削除待ちへ移ることを確認します。
    func testSessionDeletionQueuesArchiveDeletion() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let session = SyncTestFixtures.session(vehicleID: vehicle.id, archiveDigest: "d")
        try applier.apply(.vehicle(vehicle), systemFields: Data([1]))
        try applier.apply(.driveSession(session), systemFields: Data([2]))
        try applier.applyDeletion(recordType: .driveSession, recordName: session.id)
        XCTAssertEqual(try SyncArchiveIndex(database: database).queuedDeletions(), [SyncArchiveIndex.Entry(sessionID: session.id, vehicleID: vehicle.id)])
    }

    /// 責務: 子レコードの削除の適用がその行と同期管理行だけを消すことを確認します。
    func testChildDeletionRemovesOnlyThatRow() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let maintenance = SyncTestFixtures.maintenance(vehicleID: vehicle.id)
        try applier.apply(.vehicle(vehicle), systemFields: Data([1]))
        try applier.apply(.maintenanceRecord(maintenance), systemFields: Data([2]))
        try applier.applyDeletion(recordType: .maintenanceRecord, recordName: maintenance.id)
        try database.writer.read { db in
            XCTAssertEqual(try SyncVehicleRow.fetchCount(db), 1)
            XCTAssertEqual(try SyncMaintenanceRow.fetchCount(db), 0)
            XCTAssertEqual(try SyncRecordMetadataRow.fetchCount(db), 1)
        }
    }

    /// 責務: この端末で削除待ちの車両の子は取り込まないことを確認します。
    func testChildOfLocallyDeletedVehicleIsIgnored() throws {
        let vehicle = SyncTestFixtures.vehicle(deletedAt: 9_000)
        try database.writer.write { db in try vehicle.insert(db) }
        let maintenance = SyncTestFixtures.maintenance(vehicleID: vehicle.id)
        XCTAssertEqual(try applier.apply(.maintenanceRecord(maintenance), systemFields: Data([2])), .ignored)
        try database.writer.read { db in XCTAssertEqual(try SyncMaintenanceRow.fetchCount(db), 0) }
    }

    /// 責務: 保留中の子の車両がリモートで削除されたら保留も消えることを確認します。
    func testVehicleDeletionDropsParkedChildren() throws {
        let vehicleID = SyncTestFixtures.newID()
        try applier.apply(.maintenanceRecord(SyncTestFixtures.maintenance(vehicleID: vehicleID)), systemFields: Data([2]))
        try applier.applyDeletion(recordType: .vehicle, recordName: vehicleID)
        XCTAssertEqual(try applier.parkedRecords(), [])
    }
}
