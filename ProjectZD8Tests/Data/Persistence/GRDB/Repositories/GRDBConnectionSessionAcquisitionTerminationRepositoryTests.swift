import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// session、open batch、取得境界の原子終了と回復を検証します。
final class GRDBConnectionSessionAcquisitionTerminationRepositoryTests: XCTestCase {
    /// graceful、切断、取得cancel相当の終了が開いた証拠を残しません。
    ///
    /// 責務: 3種類の終了理由でsession、batch、取得境界が同じ終端日時へ確定することを確認します。
    func testExplicitEndReasonsSealEveryOpenAcquisitionState() throws {
        for reason in [
            ConnectionSessionEndReason.userDisconnected,
            .connectionLost,
            .acquisitionFailed
        ] {
            let fixture = try makeFixture()

            let ended = try fixture.acquisition.finishSessionAcquisition(
                fixture.session,
                endedAt: fixture.endedAt,
                reason: reason
            )

            XCTAssertEqual(ended.endedAt, fixture.endedAt)
            XCTAssertEqual(ended.endReason, reason)
            let batch = try XCTUnwrap(fixture.acquisition.batches(for: fixture.session.id).first)
            XCTAssertEqual(batch.completionState, .failed)
            XCTAssertEqual(batch.failure, .persistenceFailure)
            XCTAssertEqual(batch.completedAt, fixture.endedAt)
            XCTAssertEqual(batch.requests[0].dispatchState, .dispatchBegun)
            XCTAssertNil(batch.requests[0].transportOutcome)
            XCTAssertTrue(try fixture.storage.entries(for: fixture.session.id).isEmpty)
            XCTAssertEqual(
                try fixture.acquisition.boundaryEvidence(for: fixture.session.id),
                [.started(at: Date(timeIntervalSince1970: 2)), .ended(at: fixture.endedAt, reason: reason)]
            )
        }
    }

    /// session更新失敗時にbatch sealと終了境界もrollbackします。
    ///
    /// 責務: 3種類の終了書込が部分成功を残さないことを確認します。
    func testFinishRollbackKeepsSessionBoundaryAndBatchOpen() throws {
        let fixture = try makeFixture()
        try fixture.queue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER phase4g_fail_session_finish
                BEFORE UPDATE OF endedAt ON connection_sessions
                BEGIN
                    SELECT RAISE(ABORT, 'phase4g injected finish failure');
                END
                """)
        }

        XCTAssertThrowsError(
            try fixture.acquisition.finishSessionAcquisition(
                fixture.session,
                endedAt: fixture.endedAt,
                reason: .userDisconnected
            )
        )

        XCTAssertNil(try fixture.storage.sessions(for: fixture.session.accountIdentifier).first?.endedAt)
        let boundaries = try fixture.acquisition.boundaryEvidence(for: fixture.session.id)
        XCTAssertEqual(boundaries.count, 1)
        guard case .started = boundaries[0] else { return XCTFail("開始境界が保持されていません") }
        XCTAssertNil(try fixture.acquisition.batches(for: fixture.session.id).first?.completionState)
    }

    /// process終了回復がdispatch済み要求、batch、境界、sessionを同時に閉じます。
    ///
    /// 責務: simulated terminationを再送なしのunknown evidenceと異常終了sessionへ変換します。
    func testRecoveryAtomicallyClosesInterruptedAcquisition() throws {
        let fixture = try makeFixture()

        let recovered = try fixture.acquisition.recoverInterruptedSessionAcquisitions(
            for: fixture.session.accountIdentifier,
            recoveredAt: fixture.endedAt
        )

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].endReason, .unexpectedTermination)
        let boundaries = try fixture.acquisition.boundaryEvidence(for: fixture.session.id)
        XCTAssertEqual(boundaries.count, 2)
        guard case .started = boundaries[0], case .ended = boundaries[1] else {
            return XCTFail("開始・終了境界順ではありません")
        }
        let batch = try XCTUnwrap(fixture.acquisition.batches(for: fixture.session.id).first)
        XCTAssertEqual(batch.completionState, .terminatedUnknown)
        XCTAssertEqual(batch.requests[0].transportOutcome, .unknownAfterTermination)
        XCTAssertTrue(try fixture.storage.entries(for: fixture.session.id).isEmpty)
    }

    /// 実機の時計が返すmillisecond未満の端数を持つ日時でもsessionを終了できます。
    ///
    /// 責務: SQLite日時列の精度で丸められたreadbackを理由に終了が失敗しないことを確認します。
    func testFinishSucceedsWithSubMillisecondTimestamps() throws {
        let fixture = try makeFixture(
            sessionStartedAt: Date(timeIntervalSince1970: 1.123_456_789),
            endedAt: Date(timeIntervalSince1970: 10.987_654_321)
        )

        let ended = try fixture.acquisition.finishSessionAcquisition(
            fixture.session,
            endedAt: fixture.endedAt,
            reason: .connectionLost
        )

        XCTAssertEqual(ended.endReason, .connectionLost)
        let stored = try XCTUnwrap(
            fixture.storage.sessions(for: fixture.session.accountIdentifier).first
        )
        XCTAssertNotNil(stored.endedAt)
        XCTAssertEqual(stored.endReason, .connectionLost)
        XCTAssertEqual(ended, stored)
    }

    /// 実機の時計が返すmillisecond未満の端数を持つ日時でも中断sessionを回復できます。
    ///
    /// 責務: 回復日時の丸めを理由に未終了sessionが残り続けないことを確認します。
    func testRecoverySucceedsWithSubMillisecondTimestamps() throws {
        let fixture = try makeFixture(
            sessionStartedAt: Date(timeIntervalSince1970: 1.123_456_789),
            endedAt: Date(timeIntervalSince1970: 10.987_654_321)
        )

        let recovered = try fixture.acquisition.recoverInterruptedSessionAcquisitions(
            for: fixture.session.accountIdentifier,
            recoveredAt: fixture.endedAt
        )

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].endReason, .unexpectedTermination)
        XCTAssertNotNil(
            try fixture.storage.sessions(for: fixture.session.accountIdentifier).first?.endedAt
        )
    }

    /// file-backed共有Queueへopen取得fixtureを作成します。
    ///
    /// 責務: 親session、manifest、started境界、dispatch済みopen batchを同じDBへ保存します。
    /// - Parameters:
    ///   - sessionStartedAt: 親sessionの開始日時。
    ///   - endedAt: 終了・回復へ使用する日時。
    /// - Returns: 原子終了・回復を実行できるfixture。
    private func makeFixture(
        sessionStartedAt: Date = Date(timeIntervalSince1970: 1),
        endedAt: Date = Date(timeIntervalSince1970: 10)
    ) throws -> TerminationRepositoryFixture {
        let queue = try makeTemporaryQueue()
        let storage = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let acquisition = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        let session = ConnectionSession(
            id: ConnectionSessionID(rawValue: UUID()),
            accountIdentifier: "phase4g-recovery",
            startedAt: sessionStartedAt
        )
        try storage.save(session)
        try acquisition.saveStartOnce(
            manifest: Self.makeManifest(request: OBDPIDRequest(service: 1, pid: 12)),
            startedAt: Date(timeIntervalSince1970: 2),
            for: session.id
        )
        let identity = try AcquisitionBatchIdentity(ordinal: 0)
        try acquisition.beginBatch(try Self.makeOpenBatchEvidence(identity: identity), for: session.id)
        try acquisition.markRequestDispatchBegun(requestOrdinal: 0, in: identity, for: session.id)
        return TerminationRepositoryFixture(
            queue: queue,
            storage: storage,
            acquisition: acquisition,
            session: session,
            endedAt: endedAt
        )
    }

    /// test終了時に削除される一時directory上のfile-backed Queueを作成します。
    ///
    /// 責務: 一時directoryの作成と削除登録、およびそこへのDatabaseQueue生成だけを行います。
    /// - Returns: 一時directory内のSQLiteファイルを指すQueue。
    /// - Throws: directory作成またはQueue生成の失敗。
    private func makeTemporaryQueue() throws -> DatabaseQueue {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try DatabaseQueue(path: directory.appending(path: "termination.sqlite").path)
    }

    /// 単一PIDを要求する取得manifestを作成します。
    ///
    /// 責務: fixture用の固定値でmanifest全体を組み立てます。
    /// - Parameter request: manifestへ登録する唯一のPID要求。
    /// - Returns: 要求と同じPID定義を1件持つmanifest。
    /// - Throws: 値域またはmanifestの検証失敗。
    private static func makeManifest(request: OBDPIDRequest) throws -> ConnectionSessionAcquisitionManifest {
        try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(marketingVersion: "phase4g", buildVersion: "local"),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: [request]),
            pidDefinitions: [
                AcquisitionPIDDefinitionSnapshot(
                    request: request,
                    capabilitySupport: .supported,
                    isCollectionEnabled: true,
                    definitionRevision: 1,
                    requiredByteCount: 1,
                    definitionIdentity: AcquisitionPIDDefinitionIdentity(
                        canonicalizationVersion: 1,
                        expression: "A"
                    ),
                    unit: "unit",
                    validityRange: try .inclusive(minimum: 0, maximum: 255)
                )
            ],
            acquisitionPlatform: .macOS,
            modelInputManifestVersion: 1
        )
    }

    /// 未完了のopen batch証拠を作成します。
    ///
    /// 責務: 選択のみで未dispatchの要求1件を持つ、完了前のbatch証拠を組み立てます。
    /// - Parameter identity: batchの識別子。
    /// - Returns: 完了状態・失敗を持たないopen batch証拠。
    /// - Throws: 証拠の検証失敗。
    private static func makeOpenBatchEvidence(identity: AcquisitionBatchIdentity) throws -> AcquisitionBatchEvidence {
        try AcquisitionBatchEvidence(
            identity: identity,
            generation: 1,
            policyTick: 0,
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 3),
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: [
                try PIDRequestEvidence(
                    requestOrdinal: 0,
                    manifestPIDOrdinal: 0,
                    dispatchState: .selectedOnly,
                    transportOutcome: nil,
                    valueOutcome: .notEvaluated,
                    rawSequence: nil,
                    elapsedNanoseconds: nil,
                    reasonCode: nil
                )
            ]
        )
    }
}

/// 原子終了・回復testの共有DB fixtureです。
private struct TerminationRepositoryFixture {
    /// trigger注入に使用する共有Queueです。
    let queue: DatabaseQueue
    /// sessionと取得証拠でQueueを共有するProduction storageです。
    let storage: GRDBConnectionSessionRepository
    /// `storage` と同じQueueで取得証拠を保存するProduction storageです。
    let acquisition: GRDBConnectionSessionAcquisitionRepository
    /// 終了前の親sessionです。
    let session: ConnectionSession
    /// 終了・回復へ使用する固定日時です。
    let endedAt: Date
}
