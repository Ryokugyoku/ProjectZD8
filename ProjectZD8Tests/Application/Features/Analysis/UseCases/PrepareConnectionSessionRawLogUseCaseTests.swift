import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 解析開始時のRawログオンデマンド復元を検証します。
@MainActor
final class PrepareConnectionSessionRawLogUseCaseTests: XCTestCase {
    /// 端末から退避済みのRawログをCloudKitから復元して最終閲覧日時を記録します。
    ///
    /// 責務: 解析要求が単一セッションのRawダウンロード、復元、閲覧記録を完了することを確認します。
    func testDownloadsRemovedRawAndMarksAccessTime() async throws {
        let local = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1,
            byteCount: 2,
            localState: .removed,
            cloudState: .uploaded,
            manifestDigest: "manifest",
            macImportReceipt: nil
        )
        try local.importCloudMetadata(
            ConnectionSessionCloudMetadata(session: session, manifestDigest: "manifest")
        )
        let entry = ConnectionSessionRawLogEntry(
            sequence: 0,
            observedAt: Date(timeIntervalSince1970: 105),
            batchElapsedNanoseconds: 1,
            service: 0x01,
            pid: 0x0C,
            payload: [0x1A, 0xF8]
        )
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: [entry]),
            manifestDigest: "manifest"
        )
        let cloud = RawDownloadTransferRepository(transfer: transfer)
        let accessedAt = Date(timeIntervalSince1970: 120)
        let useCase = PrepareConnectionSessionRawLogUseCase(
            rawLogRepository: local,
            transferRepository: cloud,
            now: { accessedAt }
        )

        try await useCase.execute(session: session)

        XCTAssertEqual(cloud.downloadedSessionIDs, [session.id])
        XCTAssertEqual(try local.entries(for: session.id), [entry])
        let restored = try XCTUnwrap(local.sessions(for: "account").first)
        XCTAssertEqual(restored.rawLogSummary.localState, .available)
        XCTAssertEqual(restored.rawLogSummary.lastAccessedAt, accessedAt)
    }
}

/// 単一セッションのCloudKit Raw取得をメモリ上で再現します。
@MainActor
private final class RawDownloadTransferRepository: ConnectionSessionTransferRepository {
    /// 取得で返す検証済み転送です。
    private let transfer: VerifiedConnectionSessionTransfer
    /// オンデマンド取得されたセッションIDです。
    private(set) var downloadedSessionIDs: [ConnectionSessionID] = []

    /// 固定転送を保持して生成します。
    ///
    /// 責務: Raw復元テストへ返す単一転送Payloadを固定します。
    /// - Parameter transfer: オンデマンド取得で返す転送Payload。
    init(transfer: VerifiedConnectionSessionTransfer) { self.transfer = transfer }

    /// このテストではアップロードを利用不能として失敗させます。
    ///
    /// 責務: テスト対象外のRawアップロード要求を拒否します。
    /// - Parameters:
    ///   - package: 使用しない転送Payload。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: この実装はDigestを返しません。
    /// - Throws: 常に `ConnectionSessionRepositoryError.invalidState`。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String {
        throw ConnectionSessionRepositoryError.invalidState
    }

    /// 固定転送を互換全件取得として返します。
    ///
    /// 責務: プロトコル互換の全件取得へ固定転送を供給します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 固定転送1件。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] { [transfer] }

    /// 指定セッションの固定Raw転送を返します。
    ///
    /// 責務: 1件のオンデマンドRaw取得要求を検査履歴と固定転送へ変換します。
    /// - Parameters:
    ///   - sessionID: 取得対象のセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化時に保持した検証済み転送。
    /// - Throws: 指定IDが固定転送と異なる場合の状態エラー。
    func downloadTransfer(
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws -> VerifiedConnectionSessionTransfer {
        guard sessionID == transfer.package.session.id else {
            throw ConnectionSessionRepositoryError.invalidState
        }
        downloadedSessionIDs.append(sessionID)
        return transfer
    }

    /// このテストではMac受領証公開を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外の受領証公開要求を満たします。
    /// - Parameters:
    ///   - receipt: 使用しない受領証。
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMacReceipt(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {}

    /// このテストでは空のMac受領証を返します。
    ///
    /// 責務: テスト対象外の受領証取得要求を空結果で満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadMacReceipts(for accountIdentifier: String) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] { [] }

    /// このテストでは削除マーカーなしを返します。
    ///
    /// 責務: テスト対象外の削除マーカー取得要求を空集合で満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空集合。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> { [] }

    /// このテストでは単一削除を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外の単一削除要求を満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {}

    /// このテストでは全削除を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外の全削除要求を満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {}
}
