import CloudKit
import XCTest
@testable import ProjectZD8

/// 同期レコードと `CKRecord` の変換を確認します(コンテナ不要)。
final class CloudKitRecordMapperTests: XCTestCase {
    private let mapper = CloudKitRecordMapper()

    /// 責務: 送信材料からレコードを作って読み戻すと同じ内容になることを確認します。
    private func assertRoundTrip(_ payload: SyncRecordPayload, file: StaticString = #filePath, line: UInt = #line) throws {
        let record = mapper.record(for: SyncOutgoingRecord(payload: payload, systemFields: nil))
        XCTAssertEqual(record.recordType, payload.recordType.rawValue, file: file, line: line)
        XCTAssertEqual(record.recordID.recordName, payload.recordName, file: file, line: line)
        XCTAssertEqual(record.recordID.zoneID.zoneName, CloudKitSyncConfiguration.zoneName, file: file, line: line)
        XCTAssertEqual(try mapper.payload(from: record), payload, file: file, line: line)
    }

    /// 責務: 車両・整備記録・写真が往復変換で変わらないことを確認します。
    func testVehicleMaintenanceAndPhotoRoundTrip() throws {
        let vehicle = SyncTestFixtures.vehicle(photoID: SyncTestFixtures.newID())
        try assertRoundTrip(.vehicle(vehicle))
        var bare = SyncTestFixtures.vehicle()
        bare.tankCapacityLiters = nil
        bare.modelYear = nil
        bare.obdIdentifier = "OBD-1"
        try assertRoundTrip(.vehicle(bare))
        try assertRoundTrip(.maintenanceRecord(SyncTestFixtures.maintenance(vehicleID: vehicle.id)))
        try assertRoundTrip(.photo(SyncTestFixtures.photo(vehicleID: vehicle.id)))
    }

    /// 責務: セッションは往復変換でRawの所在だけが `cloudOnly` になることを確認します。
    func testSessionRoundTripMarksRawCloudOnly() throws {
        let session = SyncTestFixtures.session(vehicleID: SyncTestFixtures.newID(), archiveDigest: "abc", sampleCount: 7)
        let record = mapper.record(for: SyncOutgoingRecord(payload: .driveSession(session), systemFields: nil))
        XCTAssertNil(record["rawAvailability"])
        XCTAssertNil(record["deletedAt"])
        var expected = session
        expected.rawAvailability = RawAvailability.cloudOnly.rawValue
        XCTAssertEqual(try mapper.payload(from: record), .driveSession(expected))
    }

    /// 責務: 子レコードが親車両への削除連鎖参照を持つことを確認します。
    func testChildrenReferenceVehicleWithDeleteSelf() throws {
        let vehicleID = SyncTestFixtures.newID()
        for payload in [
            SyncRecordPayload.maintenanceRecord(SyncTestFixtures.maintenance(vehicleID: vehicleID)),
            .photo(SyncTestFixtures.photo(vehicleID: vehicleID)),
            .driveSession(SyncTestFixtures.session(vehicleID: vehicleID)),
        ] {
            let record = mapper.record(for: SyncOutgoingRecord(payload: payload, systemFields: nil))
            let reference = try XCTUnwrap(record[CloudKitRecordMapper.Field.vehicle] as? CKRecord.Reference)
            XCTAssertEqual(reference.recordID, mapper.recordID(name: vehicleID))
            XCTAssertEqual(reference.action, .deleteSelf)
        }
    }

    /// 責務: セッションレコードは検証値だけを持ち、Rawのアセットを載せないことを確認します。
    func testSessionRecordCarriesDigestButNoAsset() throws {
        let session = SyncTestFixtures.session(vehicleID: SyncTestFixtures.newID(), archiveDigest: "ff")
        let record = mapper.record(for: SyncOutgoingRecord(payload: .driveSession(session), systemFields: nil))
        XCTAssertEqual(record[CloudKitRecordMapper.Field.archiveDigest] as? String, "ff")
        XCTAssertTrue(record.allKeys().allSatisfy { !(record[$0] is CKAsset) })
    }

    /// 責務: 写真の画像ファイルがアセットとして載ることを確認します。
    func testPhotoImageIsAttachedAsAsset() {
        let url = FileManager.default.temporaryDirectory.appending(path: "photo.jpg")
        let photo = SyncTestFixtures.photo(vehicleID: SyncTestFixtures.newID())
        let record = mapper.record(for: SyncOutgoingRecord(payload: .photo(photo), systemFields: nil, photoFileURL: url))
        XCTAssertEqual((record[CloudKitRecordMapper.Field.image] as? CKAsset)?.fileURL, url)
    }

    /// 責務: システムフィールドの往復でフィールドを含まないレコードが戻り、それを土台にできることを確認します。
    func testSystemFieldsRoundTripWithoutFields() throws {
        let vehicle = SyncTestFixtures.vehicle()
        let record = mapper.record(for: SyncOutgoingRecord(payload: .vehicle(vehicle), systemFields: nil))
        let data = CloudKitRecordMapper.encodeSystemFields(of: record)
        let decoded = try XCTUnwrap(CloudKitRecordMapper.decodeSystemFields(data))
        XCTAssertEqual(decoded.recordID, record.recordID)
        XCTAssertEqual(decoded.recordType, record.recordType)
        XCTAssertTrue(decoded.allKeys().isEmpty)

        let rebuilt = mapper.record(for: SyncOutgoingRecord(payload: .vehicle(vehicle), systemFields: data))
        XCTAssertEqual(rebuilt.recordID, record.recordID)
        XCTAssertEqual(try mapper.payload(from: rebuilt), .vehicle(vehicle))
        XCTAssertNil(CloudKitRecordMapper.decodeSystemFields(Data([0, 1, 2])))
    }

    /// 責務: 未知のレコードタイプと必須フィールドの欠落を拒否することを確認します。
    func testRejectsUnknownTypeAndMissingFields() {
        let unknown = CKRecord(recordType: "Legacy", recordID: mapper.recordID(name: "x"))
        XCTAssertThrowsError(try mapper.payload(from: unknown))
        let empty = CKRecord(recordType: SyncRecordType.vehicle.rawValue, recordID: mapper.recordID(name: "x"))
        XCTAssertThrowsError(try mapper.payload(from: empty)) { error in
            XCTAssertEqual(error as? SyncLocalStoreError, .invalidValue("vin"))
        }
    }
}
