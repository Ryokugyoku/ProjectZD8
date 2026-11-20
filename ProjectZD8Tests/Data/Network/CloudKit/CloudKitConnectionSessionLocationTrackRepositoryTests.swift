import CloudKit
import Foundation
import XCTest
@testable import ProjectZD8

/// `CloudKitConnectionSessionLocationTrackRepository` の upload・一時ファイル・概要を検証します。
///
/// 仕様: upload は同じ recordID への上書きで、返す digest は Asset のバイト列の SHA-256。一時ファイルは成功・失敗とも消える。
/// `remoteManifest` は `payloadAsset` を取得しない。一覧と削除は `...RemoteTests`、取得の検証は `...DownloadTests` が扱う。
@MainActor
final class CloudKitConnectionSessionLocationTrackRepositoryTests: XCTestCase {
    /// 差し替えるストアです。
    private var store: InMemoryCloudKitPrivateRecordStore!
    /// 検証対象です。
    private var repository: CloudKitConnectionSessionLocationTrackRepository!
    /// 変換器です(期待値の ID の算出に使います)。
    private let mapper = ConnectionSessionLocationTrackRecordMapper()
    /// テスト用のセッションです。
    private let sessionID = CloudKitLocationTrackTestValues.sessionID
    /// テスト用のアカウント識別子です。
    private let account = CloudKitLocationTrackTestValues.accountIdentifier
    /// テスト用の fingerprint です。
    private let fingerprint = CloudKitLocationTrackTestValues.accountFingerprint

    override func setUp() async throws {
        store = InMemoryCloudKitPrivateRecordStore()
        repository = CloudKitConnectionSessionLocationTrackRepository(store: store)
    }

    // MARK: upload

    /// upload が仕様どおりのレコードを1回上書きすることを検証します。
    ///
    /// 責務: タイプ・recordName・7フィールドの値と、Asset を持つことを確認します。
    func testUploadSavesRecordWithSpecifiedFields() async throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 4, eventCount: 2)
        let digest = try await repository.upload(track, for: account)
        XCTAssertEqual(store.overwriteCount, 1)
        let record = try XCTUnwrap(store.storedRecords[mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint)])
        XCTAssertEqual(record.recordType, "ConnectionSessionLocationTrack")
        XCTAssertEqual(record.recordID.recordName, "location-track-\(fingerprint)-\(sessionID.rawValue.uuidString.lowercased())")
        XCTAssertEqual(record["accountFingerprint"] as? String, fingerprint)
        XCTAssertEqual(record["sessionID"] as? String, sessionID.rawValue.uuidString.lowercased())
        XCTAssertEqual(record["payloadFormatVersion"] as? Int64, 1)
        XCTAssertEqual(record["manifestDigest"] as? String, digest)
        XCTAssertEqual(record["sampleCount"] as? Int64, 4)
        XCTAssertEqual(record["eventCount"] as? Int64, 2)
        XCTAssertNotNil(record["payloadAsset"] as? CKAsset)
    }

    /// 返り値の digest が、Asset に入れたバイト列の SHA-256 と等しいことを検証します。
    ///
    /// 責務: digest が圧縮後のバイト列にかかることと、Asset の中身が復号できることを確認します。
    func testUploadReturnsSha256OfAssetBytesAndAssetDecodesToTrack() async throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 6, eventCount: 1)
        let digest = try await repository.upload(track, for: account)
        let bytes = try XCTUnwrap(store.overwrittenAssetBytes.first)
        XCTAssertEqual(digest, CloudKitRecordDigest.sha256Hex(bytes))
        let decoded = try ConnectionSessionLocationTrackPayloadCodec().decode(
            bytes, expectedSessionID: sessionID, expectedAccountFingerprint: fingerprint
        )
        XCTAssertEqual(decoded, track)
    }

    /// 再送が同じ ID への上書きになり、レコードが1件のままであることを検証します。
    ///
    /// 責務: 2回の upload で `overwrite` が2回、保持レコードが1件であることを確認します。
    func testRepeatedUploadOverwritesSameRecord() async throws {
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 2, eventCount: 0), for: account)
        let secondDigest = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 5, eventCount: 0), for: account)
        XCTAssertEqual(store.overwriteCount, 2)
        XCTAssertEqual(store.storedRecords.count, 1)
        XCTAssertEqual(store.storedRecords.values.first?["manifestDigest"] as? String, secondDigest)
        XCTAssertEqual(store.storedRecords.values.first?["sampleCount"] as? Int64, 5)
    }

    /// 空の軌跡の upload が `.invalidState` で失敗し、何も保存しないことを検証します。
    ///
    /// 責務: 空の軌跡を送らないことを確認します。
    func testUploadEmptyTrackThrowsInvalidStateAndSavesNothing() async {
        let empty = ConnectionSessionLocationTrack(sessionID: sessionID, samples: [], events: [])
        do {
            _ = try await repository.upload(empty, for: account)
            XCTFail("空の軌跡の upload が成功しました")
        } catch {
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .invalidState)
        }
        XCTAssertEqual(store.overwriteCount, 0)
        XCTAssertTrue(store.storedRecords.isEmpty)
    }

    /// 成功した upload のあとに、一時ファイルが残らないことを検証します。
    ///
    /// 責務: `overwrite` に渡された Asset の場所が、完了後に存在しないことを確認します。
    func testUploadRemovesTemporaryFileOnSuccess() async throws {
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 3, eventCount: 0), for: account)
        let urls = store.overwrittenAssetURLs
        XCTAssertEqual(urls.count, 1)
        for url in urls {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "一時ファイルが残っています")
        }
    }

    /// 失敗した upload のあとにも、一時ファイルが残らず、エラーがそのまま伝わることを検証します。
    ///
    /// 責務: `overwrite` の失敗でも一時ファイルが消え、保存されないことを確認します。
    func testUploadRemovesTemporaryFileAndPropagatesErrorOnFailure() async throws {
        store.overwriteError = .overwrite
        do {
            _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 3, eventCount: 0), for: account)
            XCTFail("失敗が伝わりませんでした")
        } catch {
            XCTAssertEqual(error as? InMemoryCloudKitPrivateRecordStore.InjectedError, .overwrite)
        }
        XCTAssertEqual(store.overwrittenAssetURLs.count, 1)
        for url in store.overwrittenAssetURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "一時ファイルが残っています")
        }
        XCTAssertTrue(store.storedRecords.isEmpty)
    }

    // MARK: remoteManifest

    /// `remoteManifest` がレコードの概要を返し、`payloadAsset` を取得しないことを検証します。
    ///
    /// 責務: 概要の値と、`desiredKeys` が指定され `payloadAsset` を含まないことを確認します。
    func testRemoteManifestReturnsManifestWithoutRequestingAsset() async throws {
        let digest = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 7, eventCount: 2), for: account)
        let manifest = try await repository.remoteManifest(sessionID: sessionID, for: account)
        XCTAssertEqual(
            manifest,
            ConnectionSessionLocationTrackRemoteManifest(sessionID: sessionID, manifestDigest: digest, sampleCount: 7, eventCount: 2)
        )
        let requested = try XCTUnwrap(store.recordDesiredKeysHistory.last)
        let keys = try XCTUnwrap(requested, "desiredKeys が nil だと Asset まで取得されます")
        XCTAssertFalse(keys.contains("payloadAsset"))
    }

    /// レコードが無ければ `remoteManifest` が `nil` を返すことを検証します。
    ///
    /// 責務: 「無い」ことをエラーにも空データにもしないことを確認します。
    func testRemoteManifestReturnsNilWhenRecordMissing() async throws {
        let manifest = try await repository.remoteManifest(sessionID: sessionID, for: account)
        XCTAssertNil(manifest)
    }

    /// ストアの取得エラーが `remoteManifest` からそのまま伝わることを検証します。
    ///
    /// 責務: 失敗を `nil` に潰さないことを確認します。
    func testRemoteManifestPropagatesStoreError() async {
        store.fetchError = .fetch
        do {
            _ = try await repository.remoteManifest(sessionID: sessionID, for: account)
            XCTFail("失敗が伝わりませんでした")
        } catch {
            XCTAssertEqual(error as? InMemoryCloudKitPrivateRecordStore.InjectedError, .fetch)
        }
    }
}
