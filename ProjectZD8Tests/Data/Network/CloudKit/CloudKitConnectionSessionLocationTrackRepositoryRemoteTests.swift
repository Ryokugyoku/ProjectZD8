import CloudKit
import Foundation
import XCTest
@testable import ProjectZD8

/// `CloudKitConnectionSessionLocationTrackRepository` の一覧・削除を検証します。
///
/// 仕様: `remoteSessionIDs` と `deleteAll` は自分のアカウントと自分のタイプだけを対象にする。
/// `delete` は冪等で、ストアの失敗はそのまま伝わる。
@MainActor
final class CloudKitConnectionSessionLocationTrackRepositoryRemoteTests: XCTestCase {
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

    /// `remoteSessionIDs` が自分のアカウントと自分のタイプのレコードだけを返すことを検証します。
    ///
    /// 責務: 他アカウントのレコードと、他タイプのレコードを含めないことを確認します。
    func testRemoteSessionIDsReturnsOnlyOwnAccountAndType() async throws {
        let other = ConnectionSessionID()
        let own = ConnectionSessionID()
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sessionID: own, sampleCount: 1, eventCount: 0), for: account)
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 1, eventCount: 0), for: account)
        seedForeignRecords(otherSession: other)
        let ids = try await repository.remoteSessionIDs(for: account)
        XCTAssertEqual(ids, [own, sessionID])
        XCTAssertTrue(store.queries.allSatisfy {
            $0.type == "ConnectionSessionLocationTrack" && $0.field == "accountFingerprint" && $0.value == fingerprint
        })
    }

    /// レコードが無ければ `remoteSessionIDs` が空集合を返すことを検証します。
    ///
    /// 責務: 0件の場合の返り値を確認します。
    func testRemoteSessionIDsIsEmptyWhenNoRecords() async throws {
        let ids = try await repository.remoteSessionIDs(for: account)
        XCTAssertTrue(ids.isEmpty)
    }

    /// `remoteSessionIDs` が `payloadAsset` を取得しないことを検証します。
    ///
    /// 責務: 一覧の取得で Asset をダウンロードしないことを確認します。
    func testRemoteSessionIDsDoesNotRequestAsset() async throws {
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 1, eventCount: 0), for: account)
        _ = try await repository.remoteSessionIDs(for: account)
        let keys = try XCTUnwrap(store.queryDesiredKeysHistory.last ?? nil, "desiredKeys が nil だと Asset まで取得されます")
        XCTAssertFalse(keys.contains("payloadAsset"))
    }

    /// `delete` が対象のレコードだけを消すことを検証します。
    ///
    /// 責務: 他のセッションのレコードが残ることを確認します。
    func testDeleteRemovesOnlyTargetRecord() async throws {
        let keep = ConnectionSessionID()
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 1, eventCount: 0), for: account)
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sessionID: keep, sampleCount: 1, eventCount: 0), for: account)
        try await repository.delete(sessionID: sessionID, for: account)
        XCTAssertEqual(Set(store.storedRecords.keys), [mapper.recordID(sessionID: keep, accountFingerprint: fingerprint)])
    }

    /// 無いレコードの `delete` が成功し、何度でも呼べる(冪等)ことを検証します。
    ///
    /// 責務: 存在しない ID の削除と、繰り返しの削除が失敗しないことを確認します。
    func testDeleteIsIdempotent() async throws {
        try await repository.delete(sessionID: sessionID, for: account)
        try await repository.delete(sessionID: sessionID, for: account)
        XCTAssertTrue(store.storedRecords.isEmpty)
    }

    /// `delete` の削除先の ID が、アカウントとセッションから決まる recordID であることを検証します。
    ///
    /// 責務: 他アカウントの同じセッションを消さないことを確認します。
    func testDeleteTargetsAccountScopedRecordID() async throws {
        try await repository.delete(sessionID: sessionID, for: account)
        XCTAssertEqual(store.deleteRequests, [mapper.recordID(sessionID: sessionID, accountFingerprint: fingerprint)])
    }

    /// ストアの削除エラーが `delete` からそのまま伝わることを検証します。
    ///
    /// 責務: 冪等な不在以外の失敗を握りつぶさないことを確認します。
    func testDeletePropagatesStoreError() async {
        store.deleteError = .delete
        do {
            try await repository.delete(sessionID: sessionID, for: account)
            XCTFail("失敗が伝わりませんでした")
        } catch {
            XCTAssertEqual(error as? InMemoryCloudKitPrivateRecordStore.InjectedError, .delete)
        }
    }

    /// `deleteAll` が自分のアカウントの軌跡だけを消し、他のレコードを残すことを検証します。
    ///
    /// 責務: 他アカウント・他タイプのレコードが残ることを確認します。
    func testDeleteAllRemovesOnlyOwnAccountTracks() async throws {
        let other = ConnectionSessionID()
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 1, eventCount: 0), for: account)
        let second = try CloudKitLocationTrackTestValues.track(sessionID: ConnectionSessionID(), sampleCount: 1, eventCount: 0)
        _ = try await repository.upload(second, for: account)
        seedForeignRecords(otherSession: other)
        try await repository.deleteAll(for: account)
        XCTAssertEqual(store.storedRecords.count, 2)
        XCTAssertTrue(store.storedRecords.values.allSatisfy {
            $0.recordType != "ConnectionSessionLocationTrack" || ($0["accountFingerprint"] as? String) != fingerprint
        })
    }

    /// `deleteAll` の検索・削除の失敗がそのまま伝わることを検証します。
    ///
    /// 責務: 検索の失敗と削除の失敗の両方を確認します。
    func testDeleteAllPropagatesStoreErrors() async throws {
        _ = try await repository.upload(try CloudKitLocationTrackTestValues.track(sampleCount: 1, eventCount: 0), for: account)
        store.queryError = .query
        await assertDeleteAllFails(with: .query)
        store.queryError = nil
        store.deleteError = .delete
        await assertDeleteAllFails(with: .delete)
        XCTAssertEqual(store.storedRecords.count, 1, "失敗した削除でレコードが消えています")
    }

    /// `deleteAll` が指定の失敗で投げることを確認します。
    ///
    /// 責務: 投げられた失敗が注入したものと同じであることを検証します。
    private func assertDeleteAllFails(
        with expected: InMemoryCloudKitPrivateRecordStore.InjectedError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await repository.deleteAll(for: account)
            XCTFail("失敗が伝わりませんでした", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? InMemoryCloudKitPrivateRecordStore.InjectedError, expected, file: file, line: line)
        }
    }

    /// 他アカウントの軌跡と、同じ fingerprint を持つ他タイプのレコードを保持させます。
    ///
    /// 責務: 絞り込みの対象外になるべきレコードを準備します。
    private func seedForeignRecords(otherSession: ConnectionSessionID) {
        let otherFingerprint = CloudKitRecordDigest.accountFingerprint(for: "account-B")
        let foreignAccount = mapper.makeRecord(
            sessionID: otherSession, accountFingerprint: otherFingerprint, digest: String(repeating: "a", count: 64),
            sampleCount: 1, eventCount: 0, assetURL: URL(fileURLWithPath: "/tmp/unused")
        )
        let otherTypeID = CKRecord.ID(recordName: "raw-\(otherSession.rawValue.uuidString.lowercased())")
        let otherType = CKRecord(recordType: "ConnectionSessionRawLog", recordID: otherTypeID)
        otherType["accountFingerprint"] = fingerprint
        otherType["sessionID"] = otherSession.rawValue.uuidString.lowercased()
        store.seed(foreignAccount)
        store.seed(otherType)
    }
}
