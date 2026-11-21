import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの送信ユースケースが、失敗を潰さず、仕様どおりの範囲で処理を止めるか続けることを検証します。
@MainActor
final class UploadConnectionSessionLocationTracksUseCaseFailureTests: XCTestCase {
    /// テストで注入するエラーです。
    private enum InjectedError: Error, Equatable {
        /// 削除済みの取得の失敗です。
        case deletedIDs
        /// 掃除の失敗です。
        case purge
        /// アカウント削除の確認の失敗です。
        case accountDeleted
        /// 1セッションの処理の失敗です(番号で区別します)。
        case session(Int)
    }

    /// 送信するアカウントです。
    private static let account = "account-a"
    /// ユースケースへ注入する現在時刻です。
    private static let now = Date(timeIntervalSince1970: 1_900_000_000)

    /// ローカルの同期 Repository の Fake です。
    private let sync = ConnectionSessionLocationTrackSyncRepositoryFake()
    /// iCloud の Repository の Fake です。
    private let cloud = ConnectionSessionLocationTrackCloudRepositoryFake()
    /// 削除済みとして返すセッション ID です。
    private var deletedIDs: Set<ConnectionSessionID> = []
    /// 削除済みの取得で投げるエラーです。
    private var deletedIDsError: InjectedError?
    /// 削除済みの取得が呼ばれた回数です。
    private var deletedIDsRequestCount = 0
    /// アカウント削除の確認で投げるエラーです。
    private var accountDeletionError: InjectedError?

    /// 空のアカウントは不正な状態として失敗し、Repository も外部の確認も呼びません。
    ///
    /// 責務: 空文字のアカウントで `invalidState` が投げられ、呼び出しが0件であることを確認します。
    func testEmptyAccountThrowsInvalidStateWithoutAnyCall() async throws {
        _ = try addSession(sampleCount: 2)

        let error = await executeExpectingError(accountIdentifier: "")

        XCTAssertEqual(error as? ConnectionSessionRepositoryError, .invalidState)
        XCTAssertEqual(sync.calls, [])
        XCTAssertEqual(cloud.calls, [])
        XCTAssertEqual(deletedIDsRequestCount, 0)
    }

    /// 削除済みの取得が失敗したら、送信も掃除もせずにそのエラーを投げます。
    ///
    /// 責務: 削除済みのデータを復活させないため、送信0件・削除0件で同じエラーが伝わることを確認します。
    func testDeletedSessionIDsFailureThrowsWithoutUploadOrPurge() async throws {
        let sessionID = try addSession(sampleCount: 2)
        try seedRemote(ConnectionSessionID())
        deletedIDsError = .deletedIDs

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .deletedIDs)
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [])
        XCTAssertEqual(cloud.deleteCallSessionIDs(), [])
        XCTAssertEqual(sync.markUploadedCalls, [])
        XCTAssertNil(sync.storedSyncRecord(for: sessionID))
    }

    /// 掃除の削除が失敗しても送信は続け、最後にその失敗を投げます。
    ///
    /// 責務: 削除の失敗の後も送る対象が送られて記録され、実行全体は削除のエラーで終わることを確認します。
    func testPurgeDeleteFailureStillUploadsAndThrowsAtEnd() async throws {
        let sessionID = try addSession(sampleCount: 2)
        let deletedRemote = ConnectionSessionID()
        try seedRemote(deletedRemote)
        deletedIDs = [deletedRemote]
        cloud.setFailure(InjectedError.purge, for: .delete, sessionID: deletedRemote)

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .purge)
        XCTAssertEqual(cloud.deleteCallSessionIDs(), [deletedRemote])
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [sessionID])
        XCTAssertEqual(sync.storedSyncRecord(for: sessionID)?.origin, .uploaded)
    }

    /// リモートの一覧の取得が失敗しても送信は続け、最後にその失敗を投げます。
    ///
    /// 責務: 掃除の段階のどこで失敗しても、送信が止まらず失敗が潰されないことを確認します。
    func testRemoteSessionIDsFailureStillUploadsAndThrowsAtEnd() async throws {
        let sessionID = try addSession(sampleCount: 2)
        deletedIDs = [ConnectionSessionID()]
        cloud.setFailure(InjectedError.purge, for: .remoteSessionIDs)

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .purge)
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [sessionID])
        XCTAssertEqual(sync.storedSyncRecord(for: sessionID)?.origin, .uploaded)
    }

    /// アカウント削除の確認が投げたら、何も送らずにそのエラーを投げます。
    ///
    /// 責務: 送信0件・送信済みの記録0件で、確認のエラーが伝わることを確認します。
    func testAccountDeletionCheckFailureUploadsNothing() async throws {
        _ = try addSession(sampleCount: 2)
        accountDeletionError = .accountDeleted

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .accountDeleted)
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [])
        XCTAssertEqual(sync.markUploadedCalls, [])
    }

    /// 1件の送信が失敗しても残りを送り、失敗したものは未記録のまま、最初のエラーを投げます。
    ///
    /// 責務: 1件目と3件目が失敗した時、2件目が記録され、投げるのは1件目のエラーであることを確認します。
    func testSessionUploadFailureContinuesOthersAndThrowsFirstError() async throws {
        let first = try addSession(sampleCount: 1)
        let second = try addSession(sampleCount: 2)
        let third = try addSession(sampleCount: 3)
        cloud.setFailure(InjectedError.session(1), for: .upload, sessionID: first)
        cloud.setFailure(InjectedError.session(3), for: .upload, sessionID: third)

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .session(1))
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [first, second, third])
        XCTAssertNil(sync.storedSyncRecord(for: first))
        XCTAssertEqual(sync.storedSyncRecord(for: second)?.origin, .uploaded)
        XCTAssertNil(sync.storedSyncRecord(for: third))
    }

    /// 送信に失敗したセッションは、次の実行で再送されます。
    ///
    /// 責務: 失敗の注入を外した2回目の実行で、失敗したセッションだけが送られることを確認します。
    func testFailedSessionIsResentOnNextRun() async throws {
        let failing = try addSession(sampleCount: 1)
        let succeeding = try addSession(sampleCount: 2)
        cloud.setFailure(InjectedError.session(1), for: .upload, sessionID: failing)
        _ = await executeExpectingError()
        cloud.setFailure(nil, for: .upload, sessionID: failing)

        let report = try await makeUseCase().execute(accountIdentifier: Self.account)

        XCTAssertEqual(report.uploadedSessionIDs, [failing])
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [failing, succeeding, failing])
        XCTAssertEqual(sync.storedSyncRecord(for: failing)?.origin, .uploaded)
    }

    /// 送信済みの記録が失敗したら、残りを続け、そのエラーを投げます。
    ///
    /// 責務: 記録の失敗が成功として潰されず、他のセッションは送られて記録されることを確認します。
    func testMarkUploadedFailureIsThrownAndOthersContinue() async throws {
        let failing = try addSession(sampleCount: 1)
        let succeeding = try addSession(sampleCount: 2)
        sync.setFailure(InjectedError.session(1), for: .markUploaded, sessionID: failing)

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .session(1))
        XCTAssertNil(sync.storedSyncRecord(for: failing))
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [failing, succeeding])
        XCTAssertEqual(sync.storedSyncRecord(for: succeeding)?.origin, .uploaded)
    }

    /// 軌跡の読み取りが失敗したら、そのセッションは送らずに残りを続け、そのエラーを投げます。
    ///
    /// 責務: 読み取りの失敗が空の軌跡として扱われず、他のセッションは送られることを確認します。
    func testTrackReadFailureIsThrownAndOthersContinue() async throws {
        let failing = try addSession(sampleCount: 1)
        let succeeding = try addSession(sampleCount: 2)
        sync.setFailure(InjectedError.session(1), for: .track, sessionID: failing)

        let error = await executeExpectingError()

        XCTAssertEqual(error as? InjectedError, .session(1))
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [succeeding])
        XCTAssertNil(sync.storedSyncRecord(for: failing))
    }

    /// 送信中のキャンセルは、残りを送らずにすぐ `CancellationError` として投げます。
    ///
    /// 責務: 1件目でキャンセルされた時、2件目の送信が呼ばれないことを確認します。
    func testCancellationIsThrownImmediately() async throws {
        let cancelled = try addSession(sampleCount: 1)
        let remaining = try addSession(sampleCount: 2)
        cloud.setFailure(CancellationError(), for: .upload, sessionID: cancelled)

        let error = await executeExpectingError()

        XCTAssertTrue(error is CancellationError, "CancellationError ではありません: \(String(describing: error))")
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [cancelled])
        XCTAssertFalse(cloud.uploadCallSessionIDs().contains(remaining))
        XCTAssertEqual(sync.markUploadedCalls, [])
    }

    /// 失敗するはずの実行を行い、投げられたエラーを返します。
    ///
    /// 責務: 成功した場合はテストを失敗させ、`nil` を返します。
    /// - Parameter accountIdentifier: 実行するアカウント。`nil` なら送信するアカウント。
    /// - Returns: 投げられたエラー。成功した場合は `nil`。
    private func executeExpectingError(accountIdentifier: String? = nil) async -> (any Error)? {
        do {
            _ = try await makeUseCase().execute(accountIdentifier: accountIdentifier ?? Self.account)
            XCTFail("実行は失敗する必要があります")
            return nil
        } catch {
            return error
        }
    }

    /// テスト対象のユースケースを作ります。
    ///
    /// 責務: Fake・失敗を注入できる削除済みの取得とアカウント削除の確認・固定の現在時刻を注入します。
    /// - Returns: 送信ユースケース。
    private func makeUseCase() -> UploadConnectionSessionLocationTracksUseCase {
        UploadConnectionSessionLocationTracksUseCase(
            syncRepository: sync,
            cloudRepository: cloud,
            deletedSessionIDs: { [unowned self] _ in
                self.deletedIDsRequestCount += 1
                if let error = self.deletedIDsError { throw error }
                return self.deletedIDs
            },
            accountDeletionCheck: { [unowned self] _ in
                if let error = self.accountDeletionError { throw error }
            },
            now: { Self.now }
        )
    }

    /// 送信するアカウントの、同期記録の無いセッションを1件登録します。
    ///
    /// 責務: 指定件数のサンプルを持つ未送信のセッションを登録します。
    /// - Parameter sampleCount: サンプル件数。
    /// - Returns: 登録したセッション ID。
    /// - Throws: 軌跡を作れない場合のテスト失敗。
    private func addSession(sampleCount: Int) throws -> ConnectionSessionID {
        let sessionID = ConnectionSessionID()
        let track = try ConnectionSessionLocationTrackTestValues.track(sessionID: sessionID, sampleCount: sampleCount)
        sync.addSession(track, accountIdentifier: Self.account)
        return sessionID
    }

    /// 送信するアカウントのリモートのレコードを1件置きます。
    ///
    /// 責務: 他の端末が送った状況を作ります。
    /// - Parameter sessionID: レコードのセッション ID。
    /// - Throws: 軌跡を作れない場合のテスト失敗。
    private func seedRemote(_ sessionID: ConnectionSessionID) throws {
        let track = try ConnectionSessionLocationTrackTestValues.track(sessionID: sessionID, sampleCount: 1)
        cloud.seedRecord(track, digest: ConnectionSessionLocationTrackTestValues.digest("b"), accountIdentifier: Self.account)
    }
}
