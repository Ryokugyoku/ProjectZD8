import CloudKit
import Foundation
import XCTest
@testable import ProjectZD8

/// `CloudKitConnectionSessionLocationTrackRepository.download` の復元と検証を確認します。
///
/// 仕様: 保存した軌跡が digest 付きで返る。レコードが無ければ `nil`。Asset の改ざん(digest の不一致)・別のアカウント・
/// Asset の欠落・件数の不一致は `.integrityConflict`。版 2 は `.unsupportedPayloadFormat(version: 2)`。
@MainActor
final class CloudKitConnectionSessionLocationTrackRepositoryDownloadTests: XCTestCase {
    /// 差し替えるストアです。
    private var store: InMemoryCloudKitPrivateRecordStore!
    /// 検証対象です。
    private var repository: CloudKitConnectionSessionLocationTrackRepository!
    /// テストが作る一時ファイルの置き場です。
    private var directory: URL!
    /// 変換器です。
    private let mapper = ConnectionSessionLocationTrackRecordMapper()
    /// 符号化器です(保持させるバイト列の作成に使います)。
    private let codec = ConnectionSessionLocationTrackPayloadCodec()
    /// テスト用のセッションです。
    private let sessionID = CloudKitLocationTrackTestValues.sessionID
    /// テスト用のアカウント識別子です。
    private let account = CloudKitLocationTrackTestValues.accountIdentifier
    /// テスト用の fingerprint です。
    private let fingerprint = CloudKitLocationTrackTestValues.accountFingerprint

    override func setUp() async throws {
        store = InMemoryCloudKitPrivateRecordStore()
        repository = CloudKitConnectionSessionLocationTrackRepository(store: store)
        directory = try CloudKitLocationTrackTestValues.makeTemporaryDirectory()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 保持された軌跡を download すると、同じ軌跡と digest が返ることを検証します。
    ///
    /// 責務: 位置と事象を含む軌跡の復元と、digest が Asset のバイト列の SHA-256 であることを確認します。
    func testDownloadReturnsSameTrackAndDigest() async throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 8, eventCount: 3)
        let bytes = try codec.encode(track, accountFingerprint: fingerprint)
        try seed(bytes: bytes, sampleCount: 8, eventCount: 3)
        let verified = try await repository.download(sessionID: sessionID, for: account)
        XCTAssertEqual(verified, VerifiedConnectionSessionLocationTrack(track: track, manifestDigest: CloudKitRecordDigest.sha256Hex(bytes)))
    }

    /// upload したものを download すると往復で一致することを検証します。
    ///
    /// 責務: Repository の upload が保持させたレコードを、そのまま読み戻せることを確認します。
    func testDownloadReadsRecordWrittenByUpload() async throws {
        let track = try CloudKitLocationTrackTestValues.track(sampleCount: 5, eventCount: 2)
        let digest = try await repository.upload(track, for: account)
        let record = try XCTUnwrap(store.storedRecords.values.first)
        record["payloadAsset"] = CKAsset(fileURL: try writeTemporaryFile(try XCTUnwrap(store.overwrittenAssetBytes.first)))
        let verified = try await repository.download(sessionID: sessionID, for: account)
        XCTAssertEqual(verified, VerifiedConnectionSessionLocationTrack(track: track, manifestDigest: digest))
    }

    /// レコードが無ければ `nil` を返すことを検証します。
    ///
    /// 責務: 「無い」ことをエラーにも空の軌跡にもしないことを確認します。
    func testDownloadReturnsNilWhenRecordMissing() async throws {
        let verified = try await repository.download(sessionID: sessionID, for: account)
        XCTAssertNil(verified)
    }

    /// Asset が書き換えられている(digest の不一致)と `.integrityConflict` になることを検証します。
    ///
    /// 責務: レコードの digest と実際のバイト列が違う場合を確認します。
    func testDownloadWithTamperedAssetThrowsIntegrityConflict() async throws {
        let original = try codec.encode(try CloudKitLocationTrackTestValues.track(sampleCount: 3, eventCount: 0), accountFingerprint: fingerprint)
        let other = try codec.encode(try CloudKitLocationTrackTestValues.track(sampleCount: 4, eventCount: 0), accountFingerprint: fingerprint)
        try seed(bytes: other, sampleCount: 3, eventCount: 0, digest: CloudKitRecordDigest.sha256Hex(original))
        await assertDownloadFails(with: ConnectionSessionRepositoryError.integrityConflict)
    }

    /// 別のアカウントの fingerprint を持つレコードで `.integrityConflict` になることを検証します。
    ///
    /// 責務: 自分の ID に別アカウントの内容が入っている場合を確認します。
    func testDownloadWithOtherAccountRecordThrowsIntegrityConflict() async throws {
        let bytes = try codec.encode(try CloudKitLocationTrackTestValues.track(sampleCount: 2, eventCount: 0), accountFingerprint: fingerprint)
        try seed(bytes: bytes, sampleCount: 2, eventCount: 0) { $0["accountFingerprint"] = "other-account" }
        await assertDownloadFails(with: ConnectionSessionRepositoryError.integrityConflict)
    }

    /// Asset が無いレコードで `.integrityConflict` になることを検証します。
    ///
    /// 責務: `payloadAsset` の欠落を確認します。
    func testDownloadWithoutAssetThrowsIntegrityConflict() async throws {
        let bytes = try codec.encode(try CloudKitLocationTrackTestValues.track(sampleCount: 2, eventCount: 0), accountFingerprint: fingerprint)
        try seed(bytes: bytes, sampleCount: 2, eventCount: 0) { $0["payloadAsset"] = nil }
        await assertDownloadFails(with: ConnectionSessionRepositoryError.integrityConflict)
    }

    /// 件数フィールドが実際の中身と合わないと `.integrityConflict` になることを検証します。
    ///
    /// 責務: sampleCount と eventCount のそれぞれの不一致を確認します。
    func testDownloadWithCountMismatchThrowsIntegrityConflict() async throws {
        let bytes = try codec.encode(try CloudKitLocationTrackTestValues.track(sampleCount: 3, eventCount: 2), accountFingerprint: fingerprint)
        try seed(bytes: bytes, sampleCount: 99, eventCount: 2)
        await assertDownloadFails(with: ConnectionSessionRepositoryError.integrityConflict)
        try seed(bytes: bytes, sampleCount: 3, eventCount: 99)
        await assertDownloadFails(with: ConnectionSessionRepositoryError.integrityConflict)
    }

    /// 壊れたバイト列(digest は一致)で `.integrityConflict` になることを検証します。
    ///
    /// 責務: digest が正しくても、伸長できない中身を受け付けないことを確認します。
    func testDownloadWithUndecodableBytesThrowsIntegrityConflict() async throws {
        try seed(bytes: Data(repeating: 0xFF, count: 64), sampleCount: 1, eventCount: 0)
        await assertDownloadFails(with: ConnectionSessionRepositoryError.integrityConflict)
    }

    /// レコードの版が 2 の場合に `.unsupportedPayloadFormat(version: 2)` になることを検証します。
    ///
    /// 責務: 新しい版のアプリが作ったレコードを区別することを確認します。
    func testDownloadWithRecordFormatVersionTwoThrowsUnsupported() async throws {
        let bytes = try codec.encode(try CloudKitLocationTrackTestValues.track(sampleCount: 2, eventCount: 0), accountFingerprint: fingerprint)
        try seed(bytes: bytes, sampleCount: 2, eventCount: 0) { $0["payloadFormatVersion"] = Int64(2) }
        await assertDownloadFails(with: ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat(version: 2))
    }

    /// ペイロード内の版が 2 の場合に `.unsupportedPayloadFormat(version: 2)` になることを検証します。
    ///
    /// 責務: digest・件数が整合していても、中身の版で拒否することを確認します。
    func testDownloadWithPayloadFormatVersionTwoThrowsUnsupported() async throws {
        let bytes = try CloudKitLocationTrackTestValues.compress(CloudKitLocationTrackTestValues.payloadJSON(formatVersion: 2))
        try seed(bytes: bytes, sampleCount: 1, eventCount: 0)
        await assertDownloadFails(with: ConnectionSessionLocationTrackCloudError.unsupportedPayloadFormat(version: 2))
    }

    /// ペイロード内のセッションが別の場合に `.integrityConflict` になることを検証します。
    ///
    /// 責務: digest・件数が整合していても、別セッションの中身を受け付けないことを確認します。
    func testDownloadWithPayloadOfOtherSessionThrowsIntegrityConflict() async throws {
        let json = CloudKitLocationTrackTestValues.payloadJSON(sessionID: UUID().uuidString.lowercased())
        try seed(bytes: try CloudKitLocationTrackTestValues.compress(json), sampleCount: 1, eventCount: 0)
        await assertDownloadFails(with: ConnectionSessionRepositoryError.integrityConflict)
    }

    /// ストアの取得エラーが `download` からそのまま伝わることを検証します。
    ///
    /// 責務: 失敗を `nil` に潰さないことを確認します。
    func testDownloadPropagatesStoreError() async {
        store.fetchError = .fetch
        await assertDownloadFails(with: InMemoryCloudKitPrivateRecordStore.InjectedError.fetch)
    }

    /// `download` が指定の失敗で投げることを確認します。
    ///
    /// 責務: 投げられた失敗が期待と等しいことを検証します。
    private func assertDownloadFails<E: Error & Equatable>(
        with expected: E,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await repository.download(sessionID: sessionID, for: account)
            XCTFail("download が成功しました", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? E, expected, file: file, line: line)
        }
    }

    /// バイト列を Asset に持つレコードを、ストアへ保持させます。
    ///
    /// 責務: 指定バイト列を一時ファイルへ書き、digest と件数を指定してレコードを作り、`mutate` で加工してから保持させます。
    private func seed(
        bytes: Data,
        sampleCount: Int,
        eventCount: Int,
        digest: String? = nil,
        mutate: (CKRecord) -> Void = { _ in }
    ) throws {
        let record = mapper.makeRecord(
            sessionID: sessionID,
            accountFingerprint: fingerprint,
            digest: digest ?? CloudKitRecordDigest.sha256Hex(bytes),
            sampleCount: sampleCount,
            eventCount: eventCount,
            assetURL: try writeTemporaryFile(bytes)
        )
        mutate(record)
        store.seed(record)
    }

    /// バイト列を一時ファイルへ書きます。
    ///
    /// 責務: tearDown で消えるディレクトリ配下へ、一意な名前で書き出します。
    private func writeTemporaryFile(_ bytes: Data) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: url)
        return url
    }
}
