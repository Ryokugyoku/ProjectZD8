import CloudKit
import Foundation
import XCTest
@testable import ProjectZD8

/// `ConnectionSessionLocationTrackRecordMapper` の recordName・レコードの形・概要の読み取りを検証します。
///
/// 仕様: タイプ名は `ConnectionSessionLocationTrack`、recordName は `location-track-<fingerprint>-<小文字UUID>`。
/// レコードは7フィールド(accountFingerprint、sessionID、payloadFormatVersion、manifestDigest、sampleCount、eventCount、payloadAsset)を持つ。
final class ConnectionSessionLocationTrackRecordMapperTests: XCTestCase {
    /// 検証対象の変換器です。
    private let mapper = ConnectionSessionLocationTrackRecordMapper()
    /// テスト用のセッションです。
    private let sessionID = CloudKitLocationTrackTestValues.sessionID
    /// テスト用の fingerprint です。
    private let fingerprint = CloudKitLocationTrackTestValues.accountFingerprint
    /// テスト用の digest(64文字)です。
    private let digest = CloudKitRecordDigest.sha256Hex(Data("payload".utf8))
    /// テスト用の Asset の場所です(ファイルは作りません)。
    private let assetURL = URL(fileURLWithPath: "/tmp/location-track-mapper-test.bin")

    /// レコードタイプ名が仕様どおりであることを検証します。
    ///
    /// 責務: CloudKit のスキーマ名として固定された文字列を確認します。
    func testRecordTypeNameIsFixed() {
        XCTAssertEqual(ConnectionSessionLocationTrackRecordMapper.recordType, "ConnectionSessionLocationTrack")
    }

    /// recordName が `location-track-<fingerprint>-<小文字UUID>` の形であることを検証します。
    ///
    /// 責務: recordName の形式と、既定ゾーンであることを確認します。
    func testRecordIDHasSpecifiedNameShape() {
        let id = mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint)
        XCTAssertEqual(id.recordName, "location-track-\(fingerprint)-\(sessionID.rawValue.uuidString.lowercased())")
        XCTAssertEqual(id.zoneID.zoneName, CKRecordZone.ID.defaultZoneName)
    }

    /// 同じ入力からは同じ ID、セッションかアカウントが違えば別の ID になることを検証します。
    ///
    /// 責務: 再送で同じレコードへ上書きされ、他のセッション・アカウントと衝突しないことを確認します。
    func testRecordIDIsDeterministicAndDistinct() {
        let base = mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint)
        XCTAssertEqual(base, mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint))
        XCTAssertNotEqual(base, mapper.recordID(sessionID: ConnectionSessionID(), accountFingerprint: fingerprint))
        XCTAssertNotEqual(base, mapper.recordID(sessionID: sessionID, accountFingerprint: "other"))
    }

    /// `makeRecord` が型・ID・7フィールドを仕様どおりに設定することを検証します。
    ///
    /// 責務: 各フィールドの値と型(Int64、String、CKAsset)を確認します。
    func testMakeRecordSetsTypeIDAndSevenFields() throws {
        let record = makeRecord()
        XCTAssertEqual(record.recordType, "ConnectionSessionLocationTrack")
        XCTAssertEqual(record.recordID, mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint))
        XCTAssertEqual(Set(record.allKeys()), [
            "accountFingerprint", "sessionID", "payloadFormatVersion", "manifestDigest",
            "sampleCount", "eventCount", "payloadAsset"
        ])
        XCTAssertEqual(record["accountFingerprint"] as? String, fingerprint)
        XCTAssertEqual(record["sessionID"] as? String, sessionID.rawValue.uuidString.lowercased())
        XCTAssertEqual(record["payloadFormatVersion"] as? Int64, 1)
        XCTAssertEqual(record["manifestDigest"] as? String, digest)
        XCTAssertEqual(record["sampleCount"] as? Int64, 14_400)
        XCTAssertEqual(record["eventCount"] as? Int64, 3)
        XCTAssertEqual((record["payloadAsset"] as? CKAsset)?.fileURL, assetURL)
    }

    /// 作ったレコードから概要を読み戻せることを検証します。
    ///
    /// 責務: `makeRecord` と `manifest(from:)` の往復を確認します。
    func testManifestRoundTripsMakeRecord() throws {
        let manifest = try mapper.manifest(from: makeRecord(), expectedSessionID: sessionID, accountFingerprint: fingerprint)
        XCTAssertEqual(
            manifest,
            ConnectionSessionLocationTrackRemoteManifest(sessionID: sessionID, manifestDigest: digest, sampleCount: 14_400, eventCount: 3)
        )
    }

    /// 期待するセッションが `nil` なら、レコード内のセッションをそのまま採用することを検証します。
    ///
    /// 責務: 一覧取得(セッションを指定しない)の経路を確認します。
    func testManifestWithoutExpectedSessionUsesRecordSession() throws {
        let manifest = try mapper.manifest(from: makeRecord(), expectedSessionID: nil, accountFingerprint: fingerprint)
        XCTAssertEqual(manifest.sessionID, sessionID)
    }

    /// Asset を持たないレコード(`desiredKeys` で落とした形)からも概要を読めることを検証します。
    ///
    /// 責務: 概要の読み取りが Asset に依存しないことを確認します。
    func testManifestDoesNotRequirePayloadAsset() throws {
        let record = makeRecord()
        record["payloadAsset"] = nil
        XCTAssertNoThrow(try mapper.manifest(from: record, expectedSessionID: sessionID, accountFingerprint: fingerprint))
    }

    /// 期待するセッションと異なるレコードは `.integrityConflict` になることを検証します。
    ///
    /// 責務: セッション ID の不一致を確認します。
    func testManifestWithOtherSessionThrowsIntegrityConflict() {
        assertIntegrityConflict(expectedSessionID: ConnectionSessionID(), fingerprint: fingerprint, record: makeRecord())
    }

    /// 別アカウントの fingerprint を持つレコードは `.integrityConflict` になることを検証します。
    ///
    /// 責務: 別のアカウントのレコードを受け付けないことを確認します。
    func testManifestWithOtherAccountThrowsIntegrityConflict() {
        assertIntegrityConflict(expectedSessionID: sessionID, fingerprint: "other-fingerprint", record: makeRecord())
    }

    /// タイプが違うレコードは `.integrityConflict` になることを検証します。
    ///
    /// 責務: 別のレコードタイプを軌跡として読まないことを確認します。
    func testManifestWithOtherRecordTypeThrowsIntegrityConflict() {
        let source = makeRecord()
        let other = CKRecord(recordType: "ConnectionSessionRawLog", recordID: source.recordID)
        for key in source.allKeys() { other[key] = source[key] }
        assertIntegrityConflict(expectedSessionID: sessionID, fingerprint: fingerprint, record: other)
    }

    /// 必須フィールドが欠けたレコードは `.integrityConflict` になることを検証します。
    ///
    /// 責務: sessionID・manifestDigest・sampleCount・eventCount・accountFingerprint のそれぞれの欠落を確認します。
    func testManifestWithMissingFieldThrowsIntegrityConflict() {
        for key in ["sessionID", "manifestDigest", "sampleCount", "eventCount", "accountFingerprint"] {
            let record = makeRecord()
            record[key] = nil
            assertIntegrityConflict(expectedSessionID: nil, fingerprint: fingerprint, record: record, message: key)
        }
    }

    /// セッション ID が UUID として読めないレコードは `.integrityConflict` になることを検証します。
    ///
    /// 責務: 壊れた sessionID の文字列を確認します。
    func testManifestWithMalformedSessionIDThrowsIntegrityConflict() {
        let record = makeRecord()
        record["sessionID"] = "not-a-uuid"
        assertIntegrityConflict(expectedSessionID: nil, fingerprint: fingerprint, record: record)
    }

    /// 件数が負のレコードは `.integrityConflict` になることを検証します。
    ///
    /// 責務: サンプル数と事象数の負の値を確認します。
    func testManifestWithNegativeCountThrowsIntegrityConflict() {
        for key in ["sampleCount", "eventCount"] {
            let record = makeRecord()
            record[key] = Int64(-1)
            assertIntegrityConflict(expectedSessionID: nil, fingerprint: fingerprint, record: record, message: key)
        }
    }

    /// テスト用のレコードを作ります。
    ///
    /// 責務: 固定の digest・件数(14,400 / 3)でレコードを組み立てます。
    private func makeRecord() -> CKRecord {
        mapper.makeRecord(
            sessionID: sessionID, accountFingerprint: fingerprint, digest: digest,
            sampleCount: 14_400, eventCount: 3, assetURL: assetURL
        )
    }

    /// `manifest(from:)` が `.integrityConflict` で失敗することを確認します。
    ///
    /// 責務: 指定条件で概要を読み、失敗の型を検証します。
    private func assertIntegrityConflict(
        expectedSessionID: ConnectionSessionID?,
        fingerprint: String,
        record: CKRecord,
        message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try mapper.manifest(from: record, expectedSessionID: expectedSessionID, accountFingerprint: fingerprint),
            message, file: file, line: line
        ) { error in
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .integrityConflict, message, file: file, line: line)
        }
    }
}
