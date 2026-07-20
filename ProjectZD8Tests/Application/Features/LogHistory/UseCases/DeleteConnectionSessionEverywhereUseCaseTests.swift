import Foundation
import XCTest
@testable import ProjectZD8

/// 全端末セッション削除の副作用順序と状態制約を検証します。
@MainActor
final class DeleteConnectionSessionEverywhereUseCaseTests: XCTestCase {
    /// CloudKit削除が成功した後に現在端末を物理削除します。
    ///
    /// 責務: 1件の終了済みセッション削除が再アップロードを防ぐ順序で実行されることを確認します。
    func testExecuteDeletesCloudBeforeLocalRepository() async throws {
        let recorder = SessionDeletionRecorder()
        let local = SessionErasureRepositorySpy(recorder: recorder)
        let cloud = SessionTransferRepositorySpy(recorder: recorder)
        let useCase = DeleteConnectionSessionEverywhereUseCase(
            localRepository: local,
            transferRepository: cloud
        )
        var session = ConnectionSession(accountIdentifier: "account")
        session.endedAt = Date()
        session.endReason = .userDisconnected

        try await useCase.execute(session: session)

        XCTAssertEqual(recorder.events, ["cloud", "local"])
    }

    /// 取得中セッションはCloudKitにもローカルにも削除要求を出しません。
    ///
    /// 責務: 未終了セッションに対する全端末削除拒否を確認します。
    func testExecuteRejectsActiveSession() async {
        let recorder = SessionDeletionRecorder()
        let useCase = DeleteConnectionSessionEverywhereUseCase(
            localRepository: SessionErasureRepositorySpy(recorder: recorder),
            transferRepository: SessionTransferRepositorySpy(recorder: recorder)
        )

        do {
            try await useCase.execute(session: ConnectionSession(accountIdentifier: "account"))
            XCTFail("取得中セッションの削除は失敗する必要があります")
        } catch {
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .invalidState)
        }
        XCTAssertTrue(recorder.events.isEmpty)
    }
}

/// セッション削除副作用を発生順に保持します。
@MainActor
private final class SessionDeletionRecorder {
    /// 発生順の副作用名です。
    var events: [String] = []
}

/// ローカルセッション物理削除を記録します。
@MainActor
private final class SessionErasureRepositorySpy: ConnectionSessionErasureRepository {
    /// 削除順序の共有記録先です。
    private let recorder: SessionDeletionRecorder

    /// 共有記録先を固定して生成します。
    ///
    /// 責務: ローカル削除Spyを1件の順序記録先へ結び付けます。
    /// - Parameter recorder: 削除副作用を保持する共有記録先。
    init(recorder: SessionDeletionRecorder) { self.recorder = recorder }

    /// ローカル物理削除を共有履歴へ記録します。
    ///
    /// 責務: 1件のローカル削除要求を順序検証可能なイベントへ変換します。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) throws {
        recorder.events.append("local")
    }
}

/// CloudKitセッション操作のうち単体削除だけを記録します。
@MainActor
private final class SessionTransferRepositorySpy: ConnectionSessionTransferRepository {
    /// 削除順序の共有記録先です。
    private let recorder: SessionDeletionRecorder

    /// 共有記録先を固定して生成します。
    ///
    /// 責務: CloudKit削除Spyを1件の順序記録先へ結び付けます。
    /// - Parameter recorder: 削除副作用を保持する共有記録先。
    init(recorder: SessionDeletionRecorder) { self.recorder = recorder }

    /// このテストでは送信を使用しません。
    ///
    /// 責務: テスト対象外の送信要求へ固定Digestを返します。
    /// - Parameters:
    ///   - package: 使用しない転送Payload。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String { "digest" }

    /// このテストでは転送を返しません。
    ///
    /// 責務: テスト対象外の転送取得へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] { [] }

    /// このテストでは受領証を公開しません。
    ///
    /// 責務: テスト対象外の受領証公開を副作用なしで満たします。
    /// - Parameters:
    ///   - receipt: 使用しない受領証。
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMacReceipt(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {}

    /// このテストでは受領証を返しません。
    ///
    /// 責務: テスト対象外の受領証取得へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadMacReceipts(for accountIdentifier: String) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] { [] }

    /// このテストでは削除マーカーを返しません。
    ///
    /// 責務: テスト対象外の削除マーカー取得へ空集合を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空集合。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> { [] }

    /// CloudKitセッション削除を共有履歴へ記録します。
    ///
    /// 責務: 1件のCloudKit削除要求を順序検証可能なイベントへ変換します。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {
        recorder.events.append("cloud")
    }

    /// このテストではアカウント全削除を使用しません。
    ///
    /// 責務: テスト対象外のアカウント全削除を副作用なしで満たします。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {}
}
