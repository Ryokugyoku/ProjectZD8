import Foundation
@testable import ProjectZD8

/// 認証モデルテストでCloudKit運転データ操作を記録します。
@MainActor
final class AuthenticationModelTransferRepositoryFake: ConnectionSessionTransferRepository {
    /// 全削除を要求されたアカウント識別子です。
    private(set) var deletedAccountIdentifiers: [String] = []

    /// このテストでは転送送信を使用しません。
    ///
    /// 責務: テスト対象外の送信要求を固定Digestで満たします。
    /// - Parameters:
    ///   - _: 使用しない転送Payload。
    ///   - _: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_: ConnectionSessionTransferPackage, for _: String) async throws -> String { "digest" }

    /// このテストでは転送を返しません。
    ///
    /// 責務: テスト対象外の転送取得要求へ空配列を返します。
    /// - Parameter _: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadTransfers(for _: String) async throws -> [VerifiedConnectionSessionTransfer] { [] }

    /// このテストでは受領証公開を使用しません。
    ///
    /// 責務: テスト対象外の受領証公開要求を副作用なしで満たします。
    /// - Parameters:
    ///   - _: 使用しないMac受領証。
    ///   - _: 使用しないセッションID。
    ///   - _: 使用しないアカウント識別子。
    func publishMacReceipt(
        _: ConnectionSessionMacImportReceipt,
        sessionID _: ConnectionSessionID,
        for _: String
    ) async throws {
    // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// このテストでは受領証を返しません。
    ///
    /// 責務: テスト対象外の受領証取得要求へ空配列を返します。
    /// - Parameter _: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadMacReceipts(
        for _: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] { [] }

    /// このテストでは削除マーカーを返しません。
    ///
    /// 責務: テスト対象外の削除マーカー取得へ空集合を返します。
    /// - Parameter _: 使用しないアカウント識別子。
    /// - Returns: 空集合。
    func deletedSessionIDs(for _: String) async throws -> Set<ConnectionSessionID> { [] }

    /// このテストではセッション単位削除を使用しません。
    ///
    /// 責務: テスト対象外のセッション削除要求を副作用なしで満たします。
    /// - Parameters:
    ///   - _: 使用しないセッションID。
    ///   - _: 使用しないアカウント識別子。
    func deleteSession(_: ConnectionSessionID, for _: String) async throws {
    // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// CloudKit運転データ全削除を記録します。
    ///
    /// 責務: 1件のアカウント識別子を削除要求履歴へ追加します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {
        deletedAccountIdentifiers.append(accountIdentifier)
    }
}
