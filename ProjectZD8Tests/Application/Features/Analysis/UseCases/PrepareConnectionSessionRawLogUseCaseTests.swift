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
            sessionRepository: local,
            rawLogRepository: local,
            transferRepository: cloud,
            now: { accessedAt }
        )
        var reportedProgress: [Double] = []

        try await useCase.execute(session: session) { reportedProgress.append($0) }

        XCTAssertEqual(cloud.downloadedSessionIDs, [session.id])
        XCTAssertEqual(reportedProgress, [0, 1])
        XCTAssertEqual(try local.entries(for: session.id), [entry])
        let restored = try XCTUnwrap(local.sessions(for: "account").first)
        XCTAssertEqual(restored.rawLogSummary.localState, .available)
        XCTAssertEqual(restored.rawLogSummary.lastAccessedAt, accessedAt)
    }

    /// CloudKit転送でミリ秒未満が丸められた日時でも同じRawログを復元します。
    ///
    /// 責務: 実端末日時とAsset日時の小数ミリ秒差がオンデマンド復元を妨げないことを確認します。
    func testDownloadsRawWhenTransferDatesAreRoundedToMilliseconds() async throws {
        let local = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var localSession = ConnectionSession(
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 100.123_456)
        )
        localSession.endedAt = Date(timeIntervalSince1970: 110.987_654)
        localSession.endReason = .userDisconnected
        localSession.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1,
            byteCount: 2,
            localState: .removed,
            cloudState: .uploaded,
            manifestDigest: "manifest",
            macImportReceipt: nil
        )
        try local.importCloudMetadata(
            ConnectionSessionCloudMetadata(session: localSession, manifestDigest: "manifest")
        )
        var transferredSession = ConnectionSession(
            id: localSession.id,
            accountIdentifier: localSession.accountIdentifier,
            startedAt: Date(timeIntervalSince1970: 100.123)
        )
        transferredSession.endedAt = Date(timeIntervalSince1970: 110.987)
        transferredSession.endReason = localSession.endReason
        transferredSession.rawLogSummary = localSession.rawLogSummary
        let entry = ConnectionSessionRawLogEntry(
            sequence: 0,
            observedAt: Date(timeIntervalSince1970: 105.456),
            batchElapsedNanoseconds: 1,
            service: 0x01,
            pid: 0x0C,
            payload: [0x1A, 0xF8]
        )
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: transferredSession, entries: [entry]),
            manifestDigest: "manifest"
        )
        let useCase = PrepareConnectionSessionRawLogUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            transferRepository: RawDownloadTransferRepository(transfer: transfer)
        )
        let persistedBeforeRestore = try XCTUnwrap(local.sessions(for: "account").first)
        XCTAssertLessThanOrEqual(abs(persistedBeforeRestore.startedAt.timeIntervalSince(transferredSession.startedAt)), 0.001_001)
        XCTAssertLessThanOrEqual(
            abs(try XCTUnwrap(persistedBeforeRestore.endedAt).timeIntervalSince(try XCTUnwrap(transferredSession.endedAt))),
            0.001_001
        )

        try await useCase.execute(session: localSession)

        XCTAssertEqual(try local.entries(for: localSession.id), [entry])
        let restored = try XCTUnwrap(local.sessions(for: "account").first)
        XCTAssertEqual(restored.rawLogSummary.localState, .available)
        XCTAssertEqual(restored.startedAt, persistedBeforeRestore.startedAt)
        XCTAssertEqual(restored.endedAt, persistedBeforeRestore.endedAt)
    }

    /// 詳細画面が削除前の状態を保持していても最新DB状態に従ってRawログを復元します。
    ///
    /// 責務: アップロード後のローカル削除と古い画面スナップショットをオンデマンド復元成功へ変換できることを確認します。
    func testDownloadsRawUsingCurrentRepositoryStateWhenSelectedSessionIsStale() async throws {
        let local = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
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
        try local.importVerifiedTransfer(transfer)
        let staleSession = try XCTUnwrap(local.sessions(for: "account").first)
        try local.removeLocalEntries(for: session.id)
        let removedSession = try XCTUnwrap(local.sessions(for: "account").first)
        XCTAssertEqual(staleSession.rawLogSummary.localState, .available)
        XCTAssertEqual(removedSession.rawLogSummary.localState, .removed)
        let cloud = RawDownloadTransferRepository(transfer: transfer)
        let useCase = PrepareConnectionSessionRawLogUseCase(
            sessionRepository: local,
            rawLogRepository: local,
            transferRepository: cloud
        )

        try await useCase.execute(session: staleSession)

        XCTAssertEqual(cloud.downloadedSessionIDs, [session.id])
        XCTAssertEqual(try local.entries(for: session.id), [entry])
        XCTAssertEqual(try XCTUnwrap(local.sessions(for: "account").first).rawLogSummary.localState, .available)
    }

    /// 未ダウンロードセッションの選択時は容量付き確認を公開しCloudKitへ接続しません。
    ///
    /// 責務: PID時系列操作を副作用前のRaw取得確認状態へ変換することを確認します。
    func testSelectionWaitsForDownloadConfirmationAndCancellationStaysLocal() throws {
        let local = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 10,
            byteCount: 2_048,
            localState: .removed,
            cloudState: .uploaded,
            manifestDigest: "manifest",
            macImportReceipt: nil
        )
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: []),
            manifestDigest: "manifest"
        )
        let cloud = RawDownloadTransferRepository(transfer: transfer)
        let model = SessionLogAnalysisModel(
            state: .init(),
            decodeTimeline: DecodeSessionLogTimelineUseCase(
                rawLogRepository: local,
                definitionRepository: EmptyDefinitionRepository()
            ),
            prepareRawLog: PrepareConnectionSessionRawLogUseCase(
                sessionRepository: local,
                rawLogRepository: local,
                transferRepository: cloud
            )
        )

        model.send(.sessionSelected(session))

        XCTAssertEqual(model.state.phase, .awaitingDownloadConfirmation)
        XCTAssertEqual(model.state.downloadPrompt?.sessionID, session.id)
        XCTAssertEqual(model.state.downloadPrompt?.byteCount, 2_048)
        XCTAssertTrue(cloud.downloadedSessionIDs.isEmpty)

        model.send(.downloadCancelled)

        XCTAssertEqual(model.state, .init())
        XCTAssertTrue(cloud.downloadedSessionIDs.isEmpty)
    }

    /// ユーザー確認後はiCloud取得進捗段階へ遷移します。
    ///
    /// 責務: Raw取得確認操作を0パーセントから始まるダウンロード状態へ変換することを確認します。
    func testConfirmationStartsDownloadProgress() throws {
        let local = try GRDBConnectionSessionRepository(databaseQueue: DatabaseQueue())
        var session = ConnectionSession(accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 100))
        session.endedAt = Date(timeIntervalSince1970: 110)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1,
            byteCount: 512,
            localState: .removed,
            cloudState: .uploaded,
            manifestDigest: "manifest",
            macImportReceipt: nil
        )
        let transfer = VerifiedConnectionSessionTransfer(
            package: ConnectionSessionTransferPackage(session: session, entries: []),
            manifestDigest: "manifest"
        )
        let cloud = RawDownloadTransferRepository(transfer: transfer)
        let model = SessionLogAnalysisModel(
            state: .init(),
            decodeTimeline: DecodeSessionLogTimelineUseCase(
                rawLogRepository: local,
                definitionRepository: EmptyDefinitionRepository()
            ),
            prepareRawLog: PrepareConnectionSessionRawLogUseCase(
                sessionRepository: local,
                rawLogRepository: local,
                transferRepository: cloud
            )
        )
        model.send(.sessionSelected(session))

        model.send(.downloadConfirmed)

        XCTAssertEqual(model.state.phase, .downloading)
        XCTAssertEqual(model.state.downloadProgress, 0)
        XCTAssertNil(model.state.downloadPrompt)
    }
}

/// 解析状態テストへ空のPID定義一覧を提供します。
private struct EmptyDefinitionRepository: OBDPIDDefinitionRepository {
    /// 空のPID定義一覧を返します。
    ///
    /// 責務: PID定義読込要求を空配列へ変換します。
    /// - Returns: 空のPID定義配列。
    func definitions() throws -> [OBDPIDDefinition] { [] }

    /// このテストではPID定義保存を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のPID定義保存要求を満たします。
    /// - Parameter definition: 使用しないPID定義。
    func upsert(_ definition: OBDPIDDefinition) throws {}

    /// このテストでは一致するPID定義を返しません。
    ///
    /// 責務: 任意のService/PID検索を定義なしへ変換します。
    /// - Parameters:
    ///   - service: 使用しないOBD Service番号。
    ///   - pid: 使用しないPID番号。
    /// - Returns: 常に `nil`。
    func definition(service: UInt8, pid: UInt8) throws -> OBDPIDDefinition? { nil }
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
