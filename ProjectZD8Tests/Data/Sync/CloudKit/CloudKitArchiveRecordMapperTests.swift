import CloudKit
import XCTest
@testable import ProjectZD8

/// アーカイブレコード(`RTSessionArchive`)の変換を確認します(コンテナ不要)。
final class CloudKitArchiveRecordMapperTests: XCTestCase {
    private let mapper = CloudKitArchiveRecordMapper()

    /// 責務: アーカイブゾーンにセッションIDの名前で作られ、アセット・検証値・車両ID(文字列)を持つことを確認します。
    func testRecordLivesInArchiveZoneWithAssetDigestAndVehicleID() {
        let url = FileManager.default.temporaryDirectory.appending(path: "a.rtarchive")
        let record = mapper.record(sessionID: "s1", vehicleID: "v1", digest: "ab", fileURL: url)
        XCTAssertEqual(record.recordType, "RTSessionArchive")
        XCTAssertEqual(record.recordID.recordName, "s1")
        XCTAssertEqual(record.recordID.zoneID.zoneName, CloudKitSyncConfiguration.archiveZoneName)
        XCTAssertNotEqual(record.recordID.zoneID, CloudKitSyncConfiguration.zoneID)
        XCTAssertEqual((record[CloudKitArchiveRecordMapper.Field.archive] as? CKAsset)?.fileURL, url)
        XCTAssertEqual(record[CloudKitArchiveRecordMapper.Field.archiveDigest] as? String, "ab")
        XCTAssertEqual(record[CloudKitArchiveRecordMapper.Field.vehicleID] as? String, "v1")
        XCTAssertNil(record[CloudKitArchiveRecordMapper.Field.vehicleID] as? CKRecord.Reference)
    }

    /// 責務: 既存レコードの検証値が同じ時だけ同一のアーカイブとみなすことを確認します。
    func testSameArchiveDetection() {
        let url = FileManager.default.temporaryDirectory.appending(path: "a.rtarchive")
        let record = mapper.record(sessionID: "s1", vehicleID: "v1", digest: "AB", fileURL: url)
        XCTAssertTrue(CloudKitArchiveRecordMapper.isSameArchive(record, digest: "ab"))
        XCTAssertFalse(CloudKitArchiveRecordMapper.isSameArchive(record, digest: "cd"))
        let other = CKRecord(recordType: SyncRecordType.driveSession.rawValue, recordID: mapper.recordID(sessionID: "s1"))
        other[CloudKitArchiveRecordMapper.Field.archiveDigest] = "ab"
        XCTAssertFalse(CloudKitArchiveRecordMapper.isSameArchive(other, digest: "ab"))
    }

    /// 責務: サーバーの版へ上書きすると内容が差し替わることを確認します。
    func testApplyOverwritesExistingRecord() {
        let old = mapper.record(sessionID: "s1", vehicleID: "v1", digest: "old", fileURL: URL(filePath: "/tmp/old"))
        let newURL = URL(filePath: "/tmp/new")
        mapper.apply(to: old, vehicleID: "v1", digest: "new", fileURL: newURL)
        XCTAssertTrue(CloudKitArchiveRecordMapper.isSameArchive(old, digest: "new"))
        XCTAssertEqual((old[CloudKitArchiveRecordMapper.Field.archive] as? CKAsset)?.fileURL, newURL)
    }
}
