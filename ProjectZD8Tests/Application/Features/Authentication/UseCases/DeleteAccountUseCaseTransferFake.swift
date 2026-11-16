import Foundation
@testable import ProjectZD8

/// アカウント削除テストでCloudKit運転データ(接続セッション)の全削除を記録します。
@MainActor
final class DeleteAccountUseCaseTransferFake: ConnectionSessionTransferRepository {
    /// 共有記録先です。
    private let recorder: DeleteAccountUseCaseRecorder

    /// 共有記録先を注入します。
    ///
    /// 責務: 運転データ削除Fakeを1件の記録先へ結び付けます。
    /// - Parameter recorder: 副作用名を発生順に保持する記録先。
    init(recorder: DeleteAccountUseCaseRecorder) { self.recorder = recorder }

    /// 使用しない転送送信へ固定Digestを返します。
    ///
    /// 責務: 削除テストに不要な境界を満たします。
    /// - Parameters:
    ///   - _: 使用しない転送Payload。
    ///   - _: 使用しないアカウント識別子。
    /// - Returns: 固定Digest。
    func upload(_: ConnectionSessionTransferPackage, for _: String) async throws -> String { "digest" }

    /// 使用しない転送取得へ空配列を返します。
    ///
    /// 責務: 削除テストに不要な境界を満たします。
    /// - Parameter _: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadTransfers(for _: String) async throws -> [VerifiedConnectionSessionTransfer] { [] }

    /// 使用しない受領証公開を無視します。
    ///
    /// 責務: 削除テストに不要な境界を満たします。
    /// - Parameters:
    ///   - _: 使用しない受領証。
    ///   - _: 使用しないセッションID。
    ///   - _: 使用しないアカウント識別子。
    func publishMacReceipt(
        _: ConnectionSessionMacImportReceipt,
        sessionID _: ConnectionSessionID,
        for _: String
    ) async throws {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// 使用しない受領証取得へ空配列を返します。
    ///
    /// 責務: 削除テストに不要な境界を満たします。
    /// - Parameter _: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func downloadMacReceipts(
        for _: String
    ) async throws -> [(ConnectionSessionID, ConnectionSessionMacImportReceipt)] { [] }

    /// 使用しない削除マーカー取得へ空集合を返します。
    ///
    /// 責務: 削除テストに不要な境界を満たします。
    /// - Parameter _: 使用しないアカウント識別子。
    /// - Returns: 空集合。
    func deletedSessionIDs(for _: String) async throws -> Set<ConnectionSessionID> { [] }

    /// 使用しないセッション単位削除を無視します。
    ///
    /// 責務: 削除テストに不要な境界を満たします。
    /// - Parameters:
    ///   - _: 使用しないセッションID。
    ///   - _: 使用しないアカウント識別子。
    func deleteSession(_: ConnectionSessionID, for _: String) async throws {
        // このテストでは呼び出しを観測しないため、何もしない。
    }

    /// CloudKit運転データ全削除を履歴へ追加します。
    ///
    /// 責務: 1件のクラウド全削除を検証可能なイベントへ変換します。
    /// - Parameter accountIdentifier: 削除対象アカウント識別子。
    func deleteAll(for accountIdentifier: String) async throws {
        try recorder.record("delete-cloud-driving-data:\(accountIdentifier)")
    }
}
