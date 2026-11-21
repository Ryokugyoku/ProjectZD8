import Foundation
import XCTest
@testable import ProjectZD8

/// 走行ルートの送信ユースケースが、送る対象の選び方・送信済みの記録・削除済みの掃除を仕様どおりに行うことを検証します。
///
/// 失敗時の振る舞いは `UploadConnectionSessionLocationTracksUseCaseFailureTests` で検証します。
@MainActor
final class UploadConnectionSessionLocationTracksUseCaseTests: XCTestCase {
    /// 送信するアカウントです。
    private static let account = "account-a"
    /// 別のアカウントです。
    private static let otherAccount = "account-b"
    /// ユースケースへ注入する現在時刻です。
    private static let now = Date(timeIntervalSince1970: 1_900_000_000)

    /// ローカルの同期 Repository の Fake です。
    private let sync = ConnectionSessionLocationTrackSyncRepositoryFake()
    /// iCloud の Repository の Fake です。
    private let cloud = ConnectionSessionLocationTrackCloudRepositoryFake()
    /// 削除済みとして返すセッション ID です。
    private var deletedIDs: Set<ConnectionSessionID> = []
    /// 削除済みの取得に渡されたアカウントです(呼ばれた順)。
    private var deletedIDsRequests: [String] = []
    /// アカウント削除の確認に渡されたアカウントです(呼ばれた順)。
    private var accountDeletionCheckRequests: [String] = []

    /// 未送信・送信後に変化を送り、送信済み・restored・空・別アカウントは送りません。
    ///
    /// 責務: ポリシーの各状態に当たる候補のうち、送る対象だけが候補の順に送られ、報告に載ることを確認します。
    func testUploadsOnlyNotUploadedAndChangedSessionsInCandidateOrder() async throws {
        let notUploaded = try addSession(sampleCount: 3, eventCount: 1)
        let changed = try addSession(sampleCount: 3, recordedSampleCount: 2, origin: .uploaded)
        let unchanged = try addSession(sampleCount: 2, recordedSampleCount: 2, origin: .uploaded)
        let restored = try addSession(sampleCount: 4, recordedSampleCount: 2, origin: .restored)
        let empty = try addSession(sampleCount: 0)
        let otherAccount = try addSession(sampleCount: 2, accountIdentifier: Self.otherAccount)

        let report = try await makeUseCase().execute(accountIdentifier: Self.account)

        XCTAssertEqual(report.uploadedSessionIDs, [notUploaded, changed])
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [notUploaded, changed])
        XCTAssertEqual(
            cloud.uploadedTracks,
            [try XCTUnwrap(sync.storedTrack(for: notUploaded)), try XCTUnwrap(sync.storedTrack(for: changed))]
        )
        for skipped in [unchanged, restored, empty, otherAccount] {
            XCTAssertFalse(cloud.uploadCallSessionIDs().contains(skipped))
        }
        XCTAssertEqual(report.purgedSessionIDs, [])
        XCTAssertTrue(sync.calls.contains(.uploadCandidates(accountIdentifier: Self.account)))
    }

    /// 状態変化だけで点が無いセッションも送ります。
    ///
    /// 責務: サンプル0件・事象1件以上の軌跡が送られ、送信済みとして記録されることを確認します。
    func testUploadsEventOnlySession() async throws {
        let eventOnly = try addSession(sampleCount: 0, eventCount: 2)

        let report = try await makeUseCase().execute(accountIdentifier: Self.account)

        XCTAssertEqual(report.uploadedSessionIDs, [eventOnly])
        XCTAssertEqual(cloud.uploadedTracks.first?.events.count, 2)
        XCTAssertEqual(sync.storedSyncRecord(for: eventOnly)?.origin, .uploaded)
    }

    /// 送信済みの記録には、送信が返した digest・読んだ軌跡の水位・注入した現在時刻を渡します。
    ///
    /// 責務: 候補を取った後・読み取りの前に点が増えても、記録する水位が送った軌跡のものであることを確認します。
    func testMarksUploadedWithReturnedDigestReadWatermarkAndNow() async throws {
        let sessionID = try addSession(sampleCount: 2)
        let grownTrack = try ConnectionSessionLocationTrackTestValues.track(sessionID: sessionID, sampleCount: 3, eventCount: 1)
        let sync = sync
        sync.setOnTrackRead { _ in sync.setTrack(grownTrack) }

        _ = try await makeUseCase().execute(accountIdentifier: Self.account)

        let digest = try XCTUnwrap(cloud.records[sessionID]?.digest)
        XCTAssertEqual(cloud.uploadedTracks, [grownTrack])
        XCTAssertEqual(
            sync.markUploadedCalls,
            [.markUploaded(sessionID: sessionID, manifestDigest: digest, watermark: grownTrack.watermark, date: Self.now)]
        )
        let candidateWatermark = try ConnectionSessionLocationTrackTestValues.track(sessionID: sessionID, sampleCount: 2).watermark
        XCTAssertNotEqual(grownTrack.watermark, candidateWatermark, "読み取り前に点が増える前提が崩れています")
    }

    /// 送信済みで水位が同じなら送らず、送信後に点が増えたら再送して記録の水位を更新します。
    ///
    /// 責務: 3回の実行で、送信 → 送らない → 再送 の順になり、最後の記録が新しい水位と digest を持つことを確認します。
    func testResendsOnlyAfterTrackGrowsAndUpdatesRecordedWatermark() async throws {
        let sessionID = try addSession(sampleCount: 2)
        let useCase = makeUseCase()

        let first = try await useCase.execute(accountIdentifier: Self.account)
        let second = try await useCase.execute(accountIdentifier: Self.account)
        let grown = try ConnectionSessionLocationTrackTestValues.track(sessionID: sessionID, sampleCount: 5, eventCount: 1)
        sync.setTrack(grown)
        let third = try await useCase.execute(accountIdentifier: Self.account)

        XCTAssertEqual(first.uploadedSessionIDs, [sessionID])
        XCTAssertEqual(second.uploadedSessionIDs, [])
        XCTAssertEqual(third.uploadedSessionIDs, [sessionID])
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [sessionID, sessionID])
        let record = try XCTUnwrap(sync.storedSyncRecord(for: sessionID))
        XCTAssertEqual(record.watermark, grown.watermark)
        XCTAssertEqual(record.manifestDigest, cloud.records[sessionID]?.digest)
        XCTAssertEqual(cloud.records[sessionID]?.track, grown)
    }

    /// 削除済みのセッションは送らず、掃除ではリモートにある削除済みのものだけを消します。
    ///
    /// 責務: 削除済み∩リモート だけが消され、削除済みでないリモートと、リモートに無い削除済みは消されないことを確認します。
    func testSkipsDeletedSessionsAndPurgesOnlyRemoteIntersection() async throws {
        let deletedLocal = try addSession(sampleCount: 2)
        let kept = try addSession(sampleCount: 2)
        let deletedRemoteOnly = ConnectionSessionID()
        let deletedNowhere = ConnectionSessionID()
        let liveRemote = ConnectionSessionID()
        try seedRemote(deletedLocal)
        try seedRemote(deletedRemoteOnly)
        try seedRemote(liveRemote)
        deletedIDs = [deletedLocal, deletedRemoteOnly, deletedNowhere]

        let report = try await makeUseCase().execute(accountIdentifier: Self.account)

        XCTAssertEqual(report.uploadedSessionIDs, [kept])
        XCTAssertEqual(report.purgedSessionIDs, [deletedLocal, deletedRemoteOnly])
        XCTAssertEqual(Set(cloud.deleteCallSessionIDs()), [deletedLocal, deletedRemoteOnly])
        XCTAssertEqual(cloud.deleteCallSessionIDs().count, 2)
        XCTAssertEqual(Set(cloud.records.keys), [liveRemote, kept])
        XCTAssertNil(sync.storedSyncRecord(for: deletedLocal))
    }

    /// 候補では空でなくても、読んだ軌跡が空なら送らず、記録もしません。
    ///
    /// 責務: 読み取り時点で空の軌跡を飛ばし、エラーにしないことを確認します。
    func testSkipsSessionWhoseTrackIsEmptyWhenRead() async throws {
        let sessionID = try addSession(sampleCount: 2)
        let sync = sync
        let emptyTrack = ConnectionSessionLocationTrackTestValues.emptyTrack(sessionID: sessionID)
        sync.setOnTrackRead { _ in sync.setTrack(emptyTrack) }

        let report = try await makeUseCase().execute(accountIdentifier: Self.account)

        XCTAssertEqual(report.uploadedSessionIDs, [])
        XCTAssertTrue(sync.calls.contains(.track(sessionID)))
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [])
        XCTAssertEqual(sync.markUploadedCalls, [])
    }

    /// 削除済みの取得・アカウント削除の確認・リモートの取得・送信に、実行したアカウントを渡します。
    ///
    /// 責務: アカウントに関わる外部呼び出しがすべて同じアカウントで行われることを確認します。
    func testPassesAccountToEveryAccountScopedCall() async throws {
        let sessionID = try addSession(sampleCount: 1)

        _ = try await makeUseCase().execute(accountIdentifier: Self.account)

        XCTAssertEqual(deletedIDsRequests, [Self.account])
        XCTAssertEqual(accountDeletionCheckRequests, [Self.account])
        XCTAssertTrue(cloud.calls.contains(.remoteSessionIDs(accountIdentifier: Self.account)))
        XCTAssertTrue(cloud.calls.contains(.upload(sessionID: sessionID, accountIdentifier: Self.account)))
        XCTAssertEqual(cloud.records[sessionID]?.accountIdentifier, Self.account)
    }

    /// 送る対象も削除済みも無ければ、空の報告を返し、送信も削除もしません。
    ///
    /// 責務: 何もすることが無い実行が成功し、外部へ書き込まないことを確認します。
    func testReturnsEmptyReportWhenNothingToDo() async throws {
        _ = try addSession(sampleCount: 2, recordedSampleCount: 2, origin: .uploaded)

        let report = try await makeUseCase().execute(accountIdentifier: Self.account)

        XCTAssertEqual(report, ConnectionSessionLocationTrackUploadReport(uploadedSessionIDs: [], purgedSessionIDs: []))
        XCTAssertEqual(cloud.uploadCallSessionIDs(), [])
        XCTAssertEqual(cloud.deleteCallSessionIDs(), [])
    }

    /// テスト対象のユースケースを作ります。
    ///
    /// 責務: Fake・削除済みの取得・アカウント削除の確認・固定の現在時刻を注入します。
    /// - Returns: 送信ユースケース。
    private func makeUseCase() -> UploadConnectionSessionLocationTracksUseCase {
        UploadConnectionSessionLocationTracksUseCase(
            syncRepository: sync,
            cloudRepository: cloud,
            deletedSessionIDs: { [unowned self] account in
                self.deletedIDsRequests.append(account)
                return self.deletedIDs
            },
            accountDeletionCheck: { [unowned self] account in self.accountDeletionCheckRequests.append(account) },
            now: { Self.now }
        )
    }

    /// ローカルにセッションを1件登録します。
    ///
    /// 責務: 指定件数の軌跡と、必要なら「指定件数のサンプルを送った」同期記録を持つセッションを登録します。
    /// - Parameters:
    ///   - sampleCount: 現在のサンプル件数。
    ///   - eventCount: 現在の事象件数。
    ///   - recordedSampleCount: 同期記録の水位に使うサンプル件数。`nil` なら同期記録なし。
    ///   - origin: 同期記録の由来。
    ///   - accountIdentifier: セッションのアカウント。`nil` なら送信するアカウント。
    /// - Returns: 登録したセッション ID。
    /// - Throws: 軌跡を作れない場合のテスト失敗。
    private func addSession(
        sampleCount: Int,
        eventCount: Int = 0,
        recordedSampleCount: Int? = nil,
        origin: ConnectionSessionLocationTrackSyncOrigin = .uploaded,
        accountIdentifier: String? = nil
    ) throws -> ConnectionSessionID {
        let sessionID = ConnectionSessionID()
        let track = try ConnectionSessionLocationTrackTestValues.track(
            sessionID: sessionID,
            sampleCount: sampleCount,
            eventCount: eventCount
        )
        let record = try recordedSampleCount.map { count in
            ConnectionSessionLocationTrackTestValues.syncRecord(
                sessionID: sessionID,
                origin: origin,
                digest: ConnectionSessionLocationTrackTestValues.digest("a"),
                watermark: try ConnectionSessionLocationTrackTestValues.track(sessionID: sessionID, sampleCount: count).watermark
            )
        }
        sync.addSession(track, accountIdentifier: accountIdentifier ?? Self.account, syncRecord: record)
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
