import Foundation
@testable import ProjectZD8

/// 認証系テストでCloudKit運転データ(接続セッション)の全削除を記録する共有Fakeです。
@MainActor
final class ConnectionSessionTransferRepositoryFake: ConnectionSessionTransferRepository {
    /// 全削除を要求されたアカウント識別子です。
    private(set) var deletedAccountIdentifiers: [String] = []

    /// 全削除の要求ごとに追加で実行する動作です(順序記録や失敗の注入に使います)。
    private let onDeleteAll: @MainActor (String) throws -> Void

    /// 全削除時の追加動作を注入します。
    ///
    /// 責務: 全削除の要求を、呼び出し側が指定した記録・失敗注入へ結び付けます。
    /// - Parameter onDeleteAll: 識別子を記録した後に呼ぶ動作。省略時は何もしません。
    init(onDeleteAll: @escaping @MainActor (String) throws -> Void = { _ in
        // 省略時は識別子の記録以外に何もしない。
    }) {
        self.onDeleteAll = onDeleteAll
    }

    /// 共有記録先へ全削除を順序つきで記録するFakeを生成します。
    ///
    /// 責務: アカウント削除ユースケースの副作用順序テスト用に、記録先へ結び付けたFakeを返します。
    /// - Parameter recorder: 副作用名を発生順に保持し、失敗も注入する記録先。
    /// - Returns: 全削除時に `delete-cloud-driving-data:<識別子>` を記録するFake。
    static func recording(into recorder: DeleteAccountUseCaseRecorder) -> ConnectionSessionTransferRepositoryFake {
        ConnectionSessionTransferRepositoryFake { try recorder.record("delete-cloud-driving-data:\($0)") }
    }

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
    /// - Throws: 注入された追加動作が投げるエラー。
    func deleteAll(for accountIdentifier: String) async throws {
        deletedAccountIdentifiers.append(accountIdentifier)
        try onDeleteAll(accountIdentifier)
    }
}
