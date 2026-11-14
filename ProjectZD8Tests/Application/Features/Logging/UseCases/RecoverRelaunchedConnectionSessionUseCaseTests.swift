import Foundation
import XCTest
@testable import ProjectZD8

/// プロセス復帰時の未終了セッションの欠損記録・続行可否・終了と、続行後の取得の区間・連番を検証します。
@MainActor
final class RecoverRelaunchedConnectionSessionUseCaseTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture
    /// 最後にcommitしたRawの実時刻です。
    private let lastCommittedAt = Date(timeIntervalSince1970: 1_020)

    /// 未終了セッションの復帰で processTerminated の欠損がちょうど1件、最後のcommitの時刻から記録され、開いた区間が閉じます。
    ///
    /// 責務: 欠損の件数・原因・開始・前の区間と、区間の終了理由・終了日時・最終連番を確認します。
    func testRecoveryRecordsOneProcessTerminatedGapFromLastCommit() async throws {
        let fixture = try await makeInterruptedSession()

        let outcome = try useCase(fixture).recover(try session(fixture), now: lastCommittedAt.addingTimeInterval(60))

        XCTAssertEqual(outcome, .resumable(try session(fixture), lastCommittedAt: lastCommittedAt))
        let gaps = try fixture.gaps.gaps(for: fixture.sessionID)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.cause, .processTerminated)
        XCTAssertEqual(gaps.first?.startedAt, lastCommittedAt)
        XCTAssertEqual(gaps.first?.precedingSegmentOrdinal, 0)
        let segment = try XCTUnwrap(fixture.segments.segments(for: fixture.sessionID).first)
        XCTAssertEqual(segment.endReason, .processTerminated)
        XCTAssertEqual(segment.endedAt, lastCommittedAt)
        XCTAssertEqual(segment.lastSequence, 1)
    }

    /// 猶予内で続行可能になった場合も、欠損の終了は復帰処理の現在時刻です(仕様D-1)。
    ///
    /// 責務: 続行可能の経路で、processTerminated の欠損の終了が現在時刻で記録されることを確認します。
    func testResumableRecoveryRecordsGapEndingNow() async throws {
        let fixture = try await makeInterruptedSession()
        let now = lastCommittedAt.addingTimeInterval(60)

        _ = try useCase(fixture).recover(try session(fixture), now: now)

        XCTAssertEqual(try fixture.gaps.gaps(for: fixture.sessionID).first?.endedAt, now)
    }

    /// 猶予ちょうどで続行可能になり、次の取得では processRelaunched の区間がちょうど1件開き、Rawの連番とbatch番号が既存の続きになります。
    ///
    /// 責務: 続行後の区間の開始理由・欠損の後続区間・連番・batch番号を確認します。
    func testResumedSessionContinuesWithProcessRelaunchedSegment() async throws {
        let fixture = try await makeInterruptedSession()
        let outcome = try useCase(fixture).recover(try session(fixture), now: lastCommittedAt.addingTimeInterval(180))
        XCTAssertEqual(outcome, .resumable(try session(fixture), lastCommittedAt: lastCommittedAt))

        fixture.relaunchRecorder()
        fixture.dates.set(Date(timeIntervalSince1970: 1_150))
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 30)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        let segments = try fixture.segments.segments(for: fixture.sessionID)
        XCTAssertEqual(segments.map(\.startReason), [.initial, .processRelaunched])
        XCTAssertEqual(segments.filter { $0.startReason == .processRelaunched }.count, 1)
        let gaps = try fixture.gaps.gaps(for: fixture.sessionID)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.followingSegmentOrdinal, 1)
        XCTAssertEqual(try fixture.storedRaws().map(\.sequence), [0, 1, 2])
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.sessionID).map(\.identity.ordinal), [0, 1, 2])
    }

    /// 猶予を過ぎていればセッションを最後のcommitの時刻で終了し、欠損の終了は現在時刻です。
    ///
    /// 責務: 終了の経路の結果・セッションの終了時刻・欠損の終了を確認します。
    func testExpiredRecoveryEndsSessionAtLastCommit() async throws {
        let fixture = try await makeInterruptedSession()
        let now = lastCommittedAt.addingTimeInterval(181)

        let outcome = try useCase(fixture).recover(try session(fixture), now: now)

        guard case let .ended(ended) = outcome else { return XCTFail("終了になりませんでした: \(outcome)") }
        XCTAssertEqual(ended.endedAt, lastCommittedAt)
        XCTAssertNotNil(ended.endReason)
        XCTAssertEqual(try session(fixture).endedAt, lastCommittedAt)
        XCTAssertEqual(try fixture.gaps.gaps(for: fixture.sessionID).map(\.endedAt), [now])
    }

    /// 同じ復帰処理を2回実行しても欠損は二重に記録されません。
    ///
    /// 責務: 続行可能の復帰を繰り返しても欠損が1件のままであることを確認します。
    func testRepeatedRecoveryDoesNotDuplicateGap() async throws {
        let fixture = try await makeInterruptedSession()
        let recovery = useCase(fixture)

        _ = try recovery.recover(try session(fixture), now: lastCommittedAt.addingTimeInterval(30))
        _ = try recovery.recover(try session(fixture), now: lastCommittedAt.addingTimeInterval(40))

        XCTAssertEqual(try fixture.gaps.gaps(for: fixture.sessionID).count, 1)
    }

    /// 区間が1件も無いセッションでは欠損を記録しません。
    ///
    /// 責務: 取得を始めていないセッションの復帰で欠損が作られないことを確認します。
    func testSessionWithoutSegmentsRecordsNoGap() async throws {
        let fixture = try Fixture(storage: .grdb)

        _ = try useCase(fixture).recover(try session(fixture), now: Date(timeIntervalSince1970: 30))

        XCTAssertEqual(try fixture.gaps.gaps(for: fixture.sessionID), [])
    }

    /// 欠損やセッション終了を保存できなければ、復帰処理は失敗を送出し、セッションを終了扱いにしません。
    ///
    /// 責務: 続行可能の経路の欠損保存失敗と、終了の経路のセッション終了失敗が成功扱いにならないことを確認します。
    func testStorageFailuresAreNotReportedAsSuccess() async throws {
        let fixture = try await makeInterruptedSession()
        let failingGaps = RecoverRelaunchedConnectionSessionUseCase(
            rawLogRepository: fixture.sessions, segmentRepository: fixture.segments,
            gapRepository: AcquisitionGapRepositorySpy(failsSave: true), terminationRepository: fixture.acquisition
        )
        let failingEnd = RecoverRelaunchedConnectionSessionUseCase(
            rawLogRepository: fixture.sessions, segmentRepository: AcquisitionSegmentRepositorySpy(),
            gapRepository: AcquisitionGapRepositorySpy(), terminationRepository: UnavailableConnectionSessionRepository()
        )

        XCTAssertThrowsError(try failingGaps.recover(try session(fixture), now: lastCommittedAt.addingTimeInterval(10)))
        XCTAssertThrowsError(try failingEnd.recover(try session(fixture), now: lastCommittedAt.addingTimeInterval(500)))
        XCTAssertNil(try session(fixture).endedAt)
    }

    /// 2周回を記録してcommitし、終了せずにプロセスが終わった状態を作ります。
    ///
    /// 責務: 最後のRawの実時刻を `lastCommittedAt` にした未終了セッションを返します。
    /// - Returns: GRDBの部品。
    /// - Throws: 記録の失敗。
    private func makeInterruptedSession() async throws -> Fixture {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        fixture.dates.set(Date(timeIntervalSince1970: 1_010))
        try await fixture.respondedRound(0, payload: 10)
        fixture.dates.set(lastCommittedAt)
        try await fixture.respondedRound(1, payload: 20)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        return fixture
    }

    /// 部品のGRDBを使う復帰処理を作ります。
    ///
    /// 責務: 本番の組立と同じRepositoryの組合せで復帰処理を返します。
    /// - Parameter fixture: GRDBの部品。
    /// - Returns: 復帰処理。
    private func useCase(_ fixture: Fixture) -> RecoverRelaunchedConnectionSessionUseCase {
        RecoverRelaunchedConnectionSessionUseCase(
            rawLogRepository: fixture.sessions, segmentRepository: fixture.segments,
            gapRepository: fixture.gaps, terminationRepository: fixture.acquisition
        )
    }

    /// 保存済みのセッションを読み戻します。
    ///
    /// 責務: 部品のセッションIDのセッションを返します。
    /// - Parameter fixture: GRDBの部品。
    /// - Returns: セッション。
    /// - Throws: 読込失敗、またはセッションが無い場合のエラー。
    private func session(_ fixture: Fixture) throws -> ConnectionSession {
        try XCTUnwrap(fixture.sessions.sessions(for: "account").first { $0.id == fixture.sessionID })
    }
}
