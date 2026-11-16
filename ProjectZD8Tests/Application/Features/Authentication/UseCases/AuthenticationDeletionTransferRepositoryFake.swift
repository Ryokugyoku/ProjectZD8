import Foundation
@testable import ProjectZD8

/// アカウント削除テストでCloudKit運転データ削除を記録します。
@MainActor
final class AuthenticationDeletionTransferRepositoryFake: ConnectionSessionTransferRepository {
    /// 副作用順序の共有記録先です。
    private let recorder: AuthenticationDeletionOrderRecorder

    /// CloudKit全削除時に返す任意エラーです。
    private let deleteAllError: Error?

    /// 共有記録先と任意のCloudKit削除エラーを注入します。
    ///
    /// 責務: CloudKit運転データ削除Fakeを1件の副作用順序記録先へ結び付けます。
    /// - Parameters:
    ///   - recorder: 副作用名を発生順に保持する記録先。
    ///   - deleteAllError: CloudKit全削除要求を失敗させる場合のエラー。
    init(
        recorder: AuthenticationDeletionOrderRecorder,
        deleteAllError: Error? = nil
    ) {
        self.recorder = recorder
        self.deleteAllError = deleteAllError
    }

    /// このテストでは転送送信を使用しません。
    ///
    /// 責務: テスト対象外の送信要求を固定Digestで満たします。
    /// - Parameters:
    ///   - package: 使用しない転送Payload。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_ package: ConnectionSessionTransferPackage, for accountIdentifier: String) async throws -> String { "digest" }

    /// このテストでは転送を返しません。
    ///
    /// 責務: テスト対象外の転送取得要求へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadTransfers(for accountIdentifier: String) async throws -> [VerifiedConnectionSessionTransfer] { [] }

    /// このテストでは受領証公開を使用しません。
    ///
    /// 責務: テスト対象外の受領証公開要求を副作用なしで満たします。
    /// - Parameters:
    ///   - receipt: 使用しないMac受領証。
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func publishMacReceipt(
        _ receipt: ConnectionSessionMacImportReceipt,
        sessionID: ConnectionSessionID,
        for accountIdentifier: String
    ) async throws {}

    /// このテストでは受領証を返しません。
    ///
    /// 責務: テスト対象外の受領証取得要求へ空配列を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadMacReceipts(
        for accountIdentifier: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] { [] }

    /// このテストでは削除マーカーを返しません。
    ///
    /// 責務: テスト対象外の削除マーカー取得へ空集合を返します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空集合。
    func deletedSessionIDs(for accountIdentifier: String) async throws -> Set<ConnectionSessionID> { [] }

    /// このテストではセッション単位削除を使用しません。
    ///
    /// 責務: テスト対象外のセッション削除要求を副作用なしで満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    func deleteSession(_ sessionID: ConnectionSessionID, for accountIdentifier: String) async throws {}

    /// CloudKit運転データ削除を共有履歴へ追加します。
    ///
    /// 責務: 1件のCloudKit全削除を順序検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {
        recorder.events.append("delete-cloud-driving-data:\(accountIdentifier)")
        if let deleteAllError {
            throw deleteAllError
        }
    }
}
