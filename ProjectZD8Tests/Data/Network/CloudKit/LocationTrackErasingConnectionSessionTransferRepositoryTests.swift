import Foundation
import XCTest
@testable import ProjectZD8

/// 軌跡の削除を足すデコレーターが、削除以外の11個の要件を、同じ引数・同じ返り値でそのまま base へ転送し、
/// 軌跡側を呼ばないことを検証します(extension の既定実装に落ちていないことの確認)。
///
/// `deleteSession` と `deleteAll` は `LocationTrackErasingConnectionSessionTransferRepositoryDeletionTests` で検証します。
@MainActor
final class LocationTrackErasingConnectionSessionTransferRepositoryTests: XCTestCase {
    /// 呼び出すアカウントです。
    private static let account = "account-a"

    /// base の Spy です。
    private let base = RecordingConnectionSessionTransferRepositorySpy()
    /// 軌跡側の Fake です。
    private let locationTracks = ConnectionSessionLocationTrackCloudRepositoryFake()
    /// 引数に使うセッションです。
    private let sessionID = ConnectionSessionID()
    /// 進捗のクロージャへ届いた値です(届いた順)。
    private var reportedProgress: [Double] = []

    /// `publishMetadata` を同じ引数で base へ転送します。
    ///
    /// 責務: 既定実装(何もしない)に落ちず、base が1回呼ばれることを確認します。
    func testPublishMetadataIsForwarded() async throws {
        try await makeRepository().publishMetadata(metadata(), for: Self.account)

        assertOnlyBaseCalled(.publishMetadata(metadata(), accountIdentifier: Self.account))
    }

    /// `downloadMetadata` を転送し、base の返り値をそのまま返します。
    ///
    /// 責務: 既定実装(空を返す)に落ちず、base の値が返ることを確認します。
    func testDownloadMetadataIsForwardedAndReturnsBaseValue() async throws {
        base.metadataToReturn = [metadata()]

        let result = try await makeRepository().downloadMetadata(for: Self.account)

        XCTAssertEqual(result, [metadata()])
        assertOnlyBaseCalled(.downloadMetadata(accountIdentifier: Self.account))
    }

    /// `downloadTransferManifests` を転送し、base の返り値をそのまま返します。
    ///
    /// 責務: 既定実装(`downloadTransfers` から組み立てる)に落ちず、base の値が返ることを確認します。
    func testDownloadTransferManifestsIsForwardedAndReturnsBaseValue() async throws {
        base.manifestsToReturn = [sessionID: "manifest"]

        let result = try await makeRepository().downloadTransferManifests(for: Self.account)

        XCTAssertEqual(result, [sessionID: "manifest"])
        assertOnlyBaseCalled(.downloadTransferManifests(accountIdentifier: Self.account))
    }

    /// 進捗なしの `downloadTransfer` を転送し、base の返り値をそのまま返します。
    ///
    /// 責務: 既定実装(`downloadTransfers` から探す)に落ちず、base の値が返ることを確認します。
    func testDownloadTransferIsForwardedAndReturnsBaseValue() async throws {
        base.transferToReturn = transfer(digest: "download")

        let result = try await makeRepository().downloadTransfer(sessionID: sessionID, for: Self.account)

        XCTAssertEqual(result, transfer(digest: "download"))
        assertOnlyBaseCalled(.downloadTransfer(sessionID, accountIdentifier: Self.account))
    }

    /// 進捗つきの `downloadTransfer` を転送し、進捗のクロージャも base へ渡します。
    ///
    /// 責務: 既定実装(0と1だけを通知)に落ちず、base の進捗と返り値がそのまま届くことを確認します。
    func testDownloadTransferWithProgressIsForwardedWithProgress() async throws {
        base.transferToReturn = transfer(digest: "progress")
        let repository = makeRepository()

        let result = try await repository.downloadTransfer(sessionID: sessionID, for: Self.account) { [unowned self] in
            self.reportedProgress.append($0)
        }

        XCTAssertEqual(result, transfer(digest: "progress"))
        XCTAssertEqual(reportedProgress, [0.25, 0.75])
        assertOnlyBaseCalled(.downloadTransferWithProgress(sessionID, accountIdentifier: Self.account))
    }

    /// 進捗なしの `upload` を転送し、base の digest をそのまま返します。
    ///
    /// 責務: 同じ転送とアカウントで base が1回呼ばれ、その digest が返ることを確認します。
    func testUploadIsForwardedAndReturnsBaseDigest() async throws {
        base.digestToReturn = "uploaded-digest"

        let digest = try await makeRepository().upload(package(), for: Self.account)

        XCTAssertEqual(digest, "uploaded-digest")
        assertOnlyBaseCalled(.upload(package(), accountIdentifier: Self.account))
    }

    /// 進捗つきの `upload` を転送し、進捗のクロージャも base へ渡します。
    ///
    /// 責務: 既定実装(進捗なしの upload を呼ぶ)に落ちず、base の進捗と digest がそのまま届くことを確認します。
    func testUploadWithProgressIsForwardedWithProgress() async throws {
        base.digestToReturn = "progress-digest"
        let repository = makeRepository()

        let digest = try await repository.upload(package(), for: Self.account) { [unowned self] in
            self.reportedProgress.append($0)
        }

        XCTAssertEqual(digest, "progress-digest")
        XCTAssertEqual(reportedProgress, [0.25, 0.75])
        assertOnlyBaseCalled(.uploadWithProgress(package(), accountIdentifier: Self.account))
    }

    /// `downloadTransfers` を転送し、base の返り値をそのまま返します。
    ///
    /// 責務: 同じアカウントで base が1回呼ばれ、その一覧が返ることを確認します。
    func testDownloadTransfersIsForwardedAndReturnsBaseValue() async throws {
        base.transfersToReturn = [transfer(digest: "one"), transfer(digest: "two")]

        let result = try await makeRepository().downloadTransfers(for: Self.account)

        XCTAssertEqual(result, [transfer(digest: "one"), transfer(digest: "two")])
        assertOnlyBaseCalled(.downloadTransfers(accountIdentifier: Self.account))
    }

    /// `publishMacReceipt` を同じ引数で base へ転送します。
    ///
    /// 責務: 受領証・セッション・アカウントが同じ値で base へ届くことを確認します。
    func testPublishMacReceiptIsForwarded() async throws {
        try await makeRepository().publishMacReceipt(receipt(), sessionID: sessionID, for: Self.account)

        assertOnlyBaseCalled(.publishMacReceipt(receipt(), sessionID, accountIdentifier: Self.account))
    }

    /// `downloadMacReceipts` を転送し、base の返り値をそのまま返します。
    ///
    /// 責務: 同じアカウントで base が1回呼ばれ、その受領証の組が順序どおり返ることを確認します。
    func testDownloadMacReceiptsIsForwardedAndReturnsBaseValue() async throws {
        let otherID = ConnectionSessionID()
        base.receiptsToReturn = [(sessionID, receipt()), (otherID, receipt())]

        let result = try await makeRepository().downloadMacReceipts(for: Self.account)

        XCTAssertEqual(result.map(\.0), [sessionID, otherID])
        XCTAssertEqual(result.map(\.1), [receipt(), receipt()])
        assertOnlyBaseCalled(.downloadMacReceipts(accountIdentifier: Self.account))
    }

    /// `deletedSessionIDs` を転送し、base の返り値をそのまま返します。
    ///
    /// 責務: 同じアカウントで base が1回呼ばれ、その集合が返ることを確認します。
    func testDeletedSessionIDsIsForwardedAndReturnsBaseValue() async throws {
        base.deletedIDsToReturn = [sessionID]

        let result = try await makeRepository().deletedSessionIDs(for: Self.account)

        XCTAssertEqual(result, [sessionID])
        assertOnlyBaseCalled(.deletedSessionIDs(accountIdentifier: Self.account))
    }

    /// テスト対象のデコレーターを作ります。
    ///
    /// 責務: Spy の base と Fake の軌跡側で包みます。
    /// - Returns: デコレーター。
    private func makeRepository() -> LocationTrackErasingConnectionSessionTransferRepository {
        LocationTrackErasingConnectionSessionTransferRepository(base: base, locationTracks: locationTracks)
    }

    /// base だけが、期待した呼び出しで1回呼ばれたことを確認します。
    ///
    /// 責務: base の記録が期待の1件と一致し、軌跡側の記録が空であることを確かめます。
    /// - Parameters:
    ///   - expected: base に期待する呼び出し。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    private func assertOnlyBaseCalled(
        _ expected: RecordingConnectionSessionTransferRepositorySpy.Call,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(base.calls, [expected], file: file, line: line)
        XCTAssertEqual(locationTracks.calls, [], "軌跡側が呼ばれました", file: file, line: line)
    }

    /// 引数に使う転送を作ります。
    ///
    /// 責務: 対象セッションの、Raw を持たない転送を返します。
    /// - Returns: 転送。
    private func package() -> ConnectionSessionTransferPackage {
        ConnectionSessionTransferPackage(sessionID: sessionID, accountIdentifier: Self.account, entries: [])
    }

    /// 返り値に使う検証済みの転送を作ります。
    ///
    /// 責務: 対象セッションの転送と、区別できる digest を組み合わせて返します。
    /// - Parameter digest: digest。
    /// - Returns: 検証済みの転送。
    private func transfer(digest: String) -> VerifiedConnectionSessionTransfer {
        VerifiedConnectionSessionTransfer(package: package(), manifestDigest: digest)
    }

    /// 引数と返り値に使うセッションの概要を作ります。
    ///
    /// 責務: 対象セッションの、時刻を固定した概要を返します(呼ぶたびに等しい値になります)。
    /// - Returns: セッションの概要。
    private func metadata() -> ConnectionSessionCloudMetadata {
        let session = ConnectionSession(
            id: sessionID,
            accountIdentifier: Self.account,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        return ConnectionSessionCloudMetadata(session: session, manifestDigest: "metadata")
    }

    /// 引数と返り値に使う Mac の受領証を作ります。
    ///
    /// 責務: 固定の値を持つ受領証を返します。
    /// - Returns: 受領証。
    private func receipt() -> ConnectionSessionMacImportReceipt {
        ConnectionSessionMacImportReceipt(
            deviceID: "mac-1",
            deviceName: "Mac",
            importedAt: Date(timeIntervalSince1970: 1_800_000_000),
            manifestDigest: "receipt"
        )
    }
}
