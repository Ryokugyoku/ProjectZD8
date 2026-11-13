import Foundation
import XCTest
@testable import ProjectZD8

/// 期限切れRawキャッシュのアカウント単位退避を検証します。
final class EvictStaleConnectionSessionRawLogsUseCaseTests: XCTestCase {
    /// 3日以上未閲覧のCloudKit保存済みRawだけを端末から除去します。
    ///
    /// 責務: 保持期限とCloudKit保護条件を満たすセッションだけがRepositoryへ渡ることを確認します。
    func testEvictsOnlyExpiredCloudProtectedRaw() throws {
        let expired = makeSession(id: ConnectionSessionID(), lastAccessedAt: 100, cloudState: .uploaded)
        let recent = makeSession(id: ConnectionSessionID(), lastAccessedAt: 300_000, cloudState: .uploaded)
        let unsafe = makeSession(id: ConnectionSessionID(), lastAccessedAt: 100, cloudState: .failed)
        let repository = EvictionRepository(sessions: [expired, recent, unsafe])
        let useCase = EvictStaleConnectionSessionRawLogsUseCase(
            sessionRepository: repository,
            rawLogRepository: repository,
            now: { Date(timeIntervalSince1970: 300_000) }
        )

        try useCase.execute(accountIdentifier: "account")

        XCTAssertEqual(repository.removedSessionIDs, [expired.id])
    }

    /// 指定条件の終了済みRaw保有セッションを生成します。
    ///
    /// 責務: 退避ユースケーステストへ保持期限とCloud状態だけが異なるセッションを供給します。
    /// - Parameters:
    ///   - id: セッションの安定識別子。
    ///   - lastAccessedAt: 最終閲覧日時のUNIX秒。
    ///   - cloudState: CloudKit転送状態。
    /// - Returns: Rawを現在端末に保持する終了済みセッション。
    private func makeSession(
        id: ConnectionSessionID,
        lastAccessedAt: TimeInterval,
        cloudState: ConnectionSessionCloudSyncState
    ) -> ConnectionSession {
        var session = ConnectionSession(id: id, accountIdentifier: "account", startedAt: Date(timeIntervalSince1970: 50))
        session.endedAt = Date(timeIntervalSince1970: 60)
        session.endReason = .userDisconnected
        session.rawLogSummary = ConnectionSessionRawLogSummary(
            recordCount: 1,
            byteCount: 2,
            localState: .available,
            cloudState: cloudState,
            manifestDigest: cloudState == .uploaded ? "manifest" : nil,
            macImportReceipt: nil,
            lastAccessedAt: Date(timeIntervalSince1970: lastAccessedAt)
        )
        return session
    }
}

/// 退避対象セッションとRaw除去要求をメモリ上で記録します。
private final class EvictionRepository: ConnectionSessionRepository, ConnectionSessionRawLogRepository {
    /// 一覧取得で返すセッションです。
    private let storedSessions: [ConnectionSession]
    /// 除去要求を受けたセッションIDです。
    private(set) var removedSessionIDs: [ConnectionSessionID] = []

    /// 固定セッション一覧を保持して生成します。
    ///
    /// 責務: 退避テスト用のローカル保存状態を固定します。
    /// - Parameter sessions: 一覧取得で返すセッション。
    init(sessions: [ConnectionSession]) { storedSessions = sessions }

    /// このテストでは保存要求を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のセッション保存要求を満たします。
    /// - Parameter session: 使用しないセッション。
    func save(_ session: ConnectionSession) throws {}

    /// 固定セッション一覧を返します。
    ///
    /// 責務: 退避ユースケースへ注入済みセッションを供給します。
    /// - Parameter accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 初期化時に保持したセッション一覧。
    func sessions(for accountIdentifier: String) throws -> [ConnectionSession] { storedSessions }

    /// このテストではRaw追記を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のRaw追記要求を満たします。
    /// - Parameters:
    ///   - observation: 使用しないRaw応答。
    ///   - sessionID: 使用しないセッションID。
    func append(_ observation: OBDRawResponseObservation, to sessionID: ConnectionSessionID) throws {}

    /// このテストでは空のRawログを返します。
    ///
    /// 責務: テスト対象外のRaw照会要求を満たします。
    /// - Parameter sessionID: 使用しないセッションID。
    /// - Returns: 空配列。
    func entries(for sessionID: ConnectionSessionID) throws -> [ConnectionSessionRawLogEntry] { [] }

    /// このテストでは空の車両別Rawログを返します。
    ///
    /// 責務: テスト対象外の車両別Raw照会要求を満たします。
    /// - Parameters:
    ///   - vehicleID: 使用しない車両ID。
    ///   - accountIdentifier: 使用しないアカウント識別子。
    /// - Returns: 空配列。
    func entries(for vehicleID: VehicleID, accountIdentifier: String) throws -> [VehicleConnectionSessionRawLogEntry] { [] }

    /// このテストではCloudKit保存状態更新を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のCloudKit保存済み更新要求を満たします。
    /// - Parameters:
    ///   - sessionID: 使用しないセッションID。
    ///   - manifestDigest: 使用しないManifest。
    func markCloudUploaded(sessionID: ConnectionSessionID, manifestDigest: String) throws {}

    /// このテストではCloudKit失敗更新を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のCloudKit失敗更新要求を満たします。
    /// - Parameter sessionID: 使用しないセッションID。
    func markCloudUploadFailed(sessionID: ConnectionSessionID) throws {}

    /// このテストではMac受領証更新を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外のMac受領証更新要求を満たします。
    /// - Parameters:
    ///   - receipt: 使用しないMac受領証。
    ///   - sessionID: 使用しないセッションID。
    func markMacImported(_ receipt: ConnectionSessionMacImportReceipt, sessionID: ConnectionSessionID) throws {}

    /// このテストでは転送取込を変更なしで受け付けます。
    ///
    /// 責務: テスト対象外の転送取込要求を満たします。
    /// - Parameter transfer: 使用しない転送Payload。
    func importVerifiedTransfer(_ transfer: VerifiedConnectionSessionTransfer) throws {}

    /// Raw除去要求を検査可能な履歴へ追加します。
    ///
    /// 責務: 1件の期限切れRaw除去要求をセッションIDとして記録します。
    /// - Parameter sessionID: 除去対象のセッションID。
    func removeLocalEntries(for sessionID: ConnectionSessionID) throws { removedSessionIDs.append(sessionID) }
}
