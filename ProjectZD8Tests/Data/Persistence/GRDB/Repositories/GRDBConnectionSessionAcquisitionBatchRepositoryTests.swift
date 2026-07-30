import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// GRDB batch/request evidenceのpartial、Raw FK、readbackを検証します。
final class GRDBConnectionSessionAcquisitionBatchRepositoryTests: XCTestCase {
    /// responded Rawとrequest terminalを原子的に保存してbatchをsealします。
    ///
    /// 責務: batch開始、dispatch、Raw採番、terminal readbackが同じidentityで成立することを確認します。
    func testCompletedBatchReferencesExistingRespondedRaw() throws {
        let fixture = try makeFixture()
        let open = try makeOpenBatch(requestCount: 1)
        try fixture.acquisition.beginBatch(open, for: fixture.session.id)
        try fixture.acquisition.markRequestDispatchBegun(
            requestOrdinal: 0,
            in: open.identity,
            for: fixture.session.id
        )
        let request = try fixture.acquisition.saveRespondedRequest(
            observation: rawObservation(),
            valueOutcome: .decodedValid,
            elapsedNanoseconds: 100,
            reasonCode: nil,
            requestOrdinal: 0,
            in: open.identity,
            for: fixture.session.id
        )
        let completed = try makeTerminalBatch(
            state: .completed,
            failure: nil,
            requests: [request]
        )

        try fixture.acquisition.finishBatch(completed, for: fixture.session.id)

        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.session.id), [completed])
        XCTAssertEqual(request.rawSequence, 0)
        XCTAssertEqual(try fixture.sessions.entries(for: fixture.session.id).map(\.payload), [[0x1F, 0x40]])
        XCTAssertThrowsError(try saveResponded(in: fixture)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .duplicate)
        }
    }

    /// Raw insert失敗時はrequest terminal更新もrollbackします。
    ///
    /// 責務: Raw制約失敗がdispatch開始証拠だけを残し部分terminalを作らないことを確認します。
    func testRawInsertFailureRollsBackRequestTerminalUpdate() throws {
        let fixture = try makeDispatchedFixture()
        try fixture.queue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER test_reject_raw_insert
                BEFORE INSERT ON connection_session_raw_logs
                BEGIN SELECT RAISE(ABORT, 'injected raw failure'); END
                """)
        }

        XCTAssertThrowsError(try saveResponded(in: fixture))

        XCTAssertTrue(try fixture.sessions.entries(for: fixture.session.id).isEmpty)
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.session.id)[0].requests[0].dispatchState, .dispatchBegun)
    }

    /// request更新失敗時は先行Raw insertもrollbackします。
    ///
    /// 責務: terminal metadata制約失敗がRaw孤立行とsession集計更新を残さないことを確認します。
    func testRequestUpdateFailureRollsBackRawInsert() throws {
        let fixture = try makeDispatchedFixture()
        try fixture.queue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER test_reject_request_terminal
                BEFORE UPDATE ON connection_session_acquisition_pid_requests
                WHEN NEW.dispatchState = 'terminal'
                BEGIN SELECT RAISE(ABORT, 'injected request failure'); END
                """)
        }

        XCTAssertThrowsError(try saveResponded(in: fixture))

        XCTAssertTrue(try fixture.sessions.entries(for: fixture.session.id).isEmpty)
        XCTAssertEqual(try fixture.sessions.sessions(for: "account")[0].rawLogSummary.recordCount, 0)
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.session.id)[0].requests[0].dispatchState, .dispatchBegun)
    }

    /// canonical Raw readback不一致時はtransaction全体をrollbackします。
    ///
    /// 責務: test fixtureによるRaw改変を検出してRaw、session集計、request terminalを残さないことを確認します。
    func testCanonicalReadbackMismatchRollsBackEverything() throws {
        let fixture = try makeDispatchedFixture()
        try fixture.queue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER test_corrupt_raw_after_insert
                AFTER INSERT ON connection_session_raw_logs
                BEGIN
                    UPDATE connection_session_raw_logs
                    SET payload = X'FF'
                    WHERE sessionID = NEW.sessionID AND sequence = NEW.sequence;
                END
                """)
        }

        XCTAssertThrowsError(try saveResponded(in: fixture))

        XCTAssertTrue(try fixture.sessions.entries(for: fixture.session.id).isEmpty)
        XCTAssertEqual(try fixture.sessions.sessions(for: "account")[0].rawLogSummary.recordCount, 0)
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.session.id)[0].requests[0].dispatchState, .dispatchBegun)
    }

    /// dispatch前のresponded保存を拒否します。
    ///
    /// 責務: selected-only要求がRaw追加を伴うterminalへ飛び越せないことを確認します。
    func testRespondedBeforeDispatchIsRejectedWithoutRaw() throws {
        let fixture = try makeFixture()
        let open = try makeOpenBatch(requestCount: 1)
        try fixture.acquisition.beginBatch(open, for: fixture.session.id)

        XCTAssertThrowsError(try saveResponded(in: fixture)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertTrue(try fixture.sessions.entries(for: fixture.session.id).isEmpty)
    }

    /// sealed batchへの追記を拒否します。
    ///
    /// 責務: batch seal後に同じrequestへRawまたは異なるterminal結果を追加できないことを確認します。
    func testSealedBatchRejectsRespondedAppend() throws {
        let fixture = try makeDispatchedFixture()
        let request = try fixture.acquisition.saveNonRespondedRequest(
            outcome: .timedOut,
            elapsedNanoseconds: 100,
            reasonCode: "response_timeout",
            requestOrdinal: 0,
            in: AcquisitionBatchIdentity(ordinal: 0),
            for: fixture.session.id
        )
        try fixture.acquisition.finishBatch(
            try makeTerminalBatch(state: .failed, failure: .transportUnavailable, requests: [request]),
            for: fixture.session.id
        )

        XCTAssertThrowsError(try saveResponded(in: fixture)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertTrue(try fixture.sessions.entries(for: fixture.session.id).isEmpty)
    }

    /// exact retryとsemantic差分を区別します。
    ///
    /// 責務: 同一responded入力だけをduplicateとしpayload、value、elapsed差をconflictへ分類します。
    func testRespondedRetryDistinguishesDuplicateFromConflict() throws {
        let fixture = try makeDispatchedFixture()
        _ = try saveResponded(in: fixture)

        XCTAssertThrowsError(try saveResponded(in: fixture)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .duplicate)
        }
        XCTAssertThrowsError(try saveResponded(in: fixture, observation: rawObservation(payload: [0x00]))) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertThrowsError(try saveResponded(in: fixture, valueOutcome: .invalidValue)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertThrowsError(try saveResponded(in: fixture, elapsedNanoseconds: 101)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertEqual(try fixture.sessions.entries(for: fixture.session.id).count, 1)
    }

    /// Raw要求とmanifest PID所有関係の不一致を拒否します。
    ///
    /// 責務: 同じsessionでも異なるService/PIDのRawがrequest evidenceへ結合されないことを確認します。
    func testRawRequestOwnershipMismatchIsRejected() throws {
        let fixture = try makeDispatchedFixture()

        XCTAssertThrowsError(
            try saveResponded(
                in: fixture,
                observation: OBDRawResponseObservation(
                    observedAt: Date(timeIntervalSince1970: 11),
                    batchElapsedNanoseconds: 100,
                    request: OBDPIDRequest(service: 1, pid: 13),
                    payload: [0x20]
                )
            )
        ) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .conflict)
        }
        XCTAssertTrue(try fixture.sessions.entries(for: fixture.session.id).isEmpty)
    }

    /// 別sessionの同じRaw sequenceをrequest FKへ結合できません。
    ///
    /// 責務: composite Raw FKがsequence一致だけでは所有session不一致を受理しないことを確認します。
    func testRawForeignKeyRejectsDifferentSessionSequence() throws {
        let fixture = try makeDispatchedFixture()
        let otherSession = ConnectionSession(
            id: ConnectionSessionID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!),
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 1)
        )
        try fixture.sessions.save(otherSession)
        try fixture.sessions.append(rawObservation(), to: otherSession.id)

        XCTAssertThrowsError(
            try fixture.queue.write { database in
                try database.execute(
                    sql: """
                        UPDATE connection_session_acquisition_pid_requests
                        SET dispatchState = 'terminal', transportOutcome = 'responded',
                            valueOutcome = 'decodedValid', rawSequence = 0,
                            elapsedNanoseconds = 100, isSealed = 1
                        WHERE sessionID = ? AND batchOrdinal = 0 AND requestOrdinal = 0
                        """,
                    arguments: [fixture.session.id.rawValue.uuidString.lowercased()]
                )
            }
        )
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.session.id)[0].requests[0].dispatchState, .dispatchBegun)
    }

    /// process終了回復ではdispatch済みだけをunknownとして保持します。
    ///
    /// 責務: 未送信selected requestをcancelledへ補正せずpartial batchを復元することを確認します。
    func testTerminationKeepsSelectedOnlyRequestDistinctFromUnknownDispatch() throws {
        let fixture = try makeFixture()
        let open = try makeOpenBatch(requestCount: 2)
        try fixture.acquisition.beginBatch(open, for: fixture.session.id)
        try fixture.acquisition.markRequestDispatchBegun(
            requestOrdinal: 0,
            in: open.identity,
            for: fixture.session.id
        )
        let unknown = try PIDRequestEvidence(
            requestOrdinal: 0,
            manifestPIDOrdinal: 0,
            dispatchState: .terminal,
            transportOutcome: .unknownAfterTermination,
            valueOutcome: .notEvaluated,
            rawSequence: nil,
            elapsedNanoseconds: 100,
            reasonCode: "process_terminated_after_dispatch"
        )
        let selectedOnly = try pendingRequest(requestOrdinal: 1, manifestPIDOrdinal: 1)
        let terminated = try makeTerminalBatch(
            state: .terminatedUnknown,
            failure: .processTerminated,
            requests: [unknown, selectedOnly]
        )

        try fixture.acquisition.finishBatch(terminated, for: fixture.session.id)

        let stored = try XCTUnwrap(fixture.acquisition.batches(for: fixture.session.id).first)
        XCTAssertEqual(stored.requests[0].transportOutcome, .unknownAfterTermination)
        XCTAssertEqual(stored.requests[1].dispatchState, .selectedOnly)
        XCTAssertNil(stored.requests[1].transportOutcome)
    }

    /// Raw FKが存在しないresponded requestをrollbackします。
    ///
    /// 責務: fabricated Raw sequenceを持つrequest evidenceがbatch sealへ到達しないことを確認します。
    func testMissingRespondedRawRollsBackTerminalUpdate() throws {
        let fixture = try makeFixture()
        let open = try makeOpenBatch(requestCount: 1)
        try fixture.acquisition.beginBatch(open, for: fixture.session.id)
        let request = try PIDRequestEvidence(
            requestOrdinal: 0,
            manifestPIDOrdinal: 0,
            dispatchState: .terminal,
            transportOutcome: .responded,
            valueOutcome: .decodedValid,
            rawSequence: 99,
            elapsedNanoseconds: 100,
            reasonCode: nil
        )
        let completed = try makeTerminalBatch(state: .completed, failure: nil, requests: [request])

        XCTAssertThrowsError(try fixture.acquisition.finishBatch(completed, for: fixture.session.id))

        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.session.id), [open])
    }

    /// test用DB、session、manifest、両repositoryを生成します。
    ///
    /// 責務: batch repository testを完全な親aggregate付きfixtureへ固定します。
    /// - Returns: 同じin-memory DBを共有するtest fixture。
    private func makeFixture() throws -> BatchRepositoryFixture {
        let queue = try DatabaseQueue()
        let sessions = try GRDBConnectionSessionRepository(databaseQueue: queue)
        let acquisition = try GRDBConnectionSessionAcquisitionRepository(databaseQueue: queue)
        let session = ConnectionSession(
            id: ConnectionSessionID(rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!),
            accountIdentifier: "account",
            startedAt: Date(timeIntervalSince1970: 1)
        )
        try sessions.save(session)
        try acquisition.saveStartOnce(
            manifest: makeManifest(),
            startedAt: Date(timeIntervalSince1970: 2),
            for: session.id
        )
        return BatchRepositoryFixture(queue: queue, sessions: sessions, acquisition: acquisition, session: session)
    }

    /// open batchの先頭要求をdispatch開始済みにしたfixtureを生成します。
    ///
    /// 責務: responded原子保存testを共通の直前状態へ固定します。
    /// - Returns: 先頭要求がdispatch開始済みのGRDB fixture。
    private func makeDispatchedFixture() throws -> BatchRepositoryFixture {
        let fixture = try makeFixture()
        let open = try makeOpenBatch(requestCount: 1)
        try fixture.acquisition.beginBatch(open, for: fixture.session.id)
        try fixture.acquisition.markRequestDispatchBegun(
            requestOrdinal: 0,
            in: open.identity,
            for: fixture.session.id
        )
        return fixture
    }

    /// test用responded Raw observationを生成します。
    ///
    /// 責務: payloadだけを差し替え可能な同一時刻・要求のRaw入力を返します。
    /// - Parameter payload: 保存する未デコードbytes。
    /// - Returns: 先頭manifest PIDに対応するRaw observation。
    private func rawObservation(payload: [UInt8] = [0x1F, 0x40]) -> OBDRawResponseObservation {
        OBDRawResponseObservation(
            observedAt: Date(timeIntervalSince1970: 11),
            batchElapsedNanoseconds: 100,
            request: OBDPIDRequest(service: 1, pid: 12),
            payload: payload
        )
    }

    /// fixtureへresponded Rawとrequest evidenceを原子的に保存します。
    ///
    /// 責務: retry分類testへ変更可能なresponded入力を同じrepository呼出しで渡します。
    /// - Parameters:
    ///   - fixture: 保存対象GRDB fixture。
    ///   - observation: 保存するRaw observation。
    ///   - valueOutcome: 保存する値評価結果。
    ///   - elapsedNanoseconds: 保存するterminal経過時間。
    /// - Returns: canonical request evidence。
    /// - Throws: repositoryが返す原子保存エラー。
    private func saveResponded(
        in fixture: BatchRepositoryFixture,
        observation: OBDRawResponseObservation? = nil,
        valueOutcome: PIDRequestValueOutcome = .decodedValid,
        elapsedNanoseconds: UInt64 = 100
    ) throws -> PIDRequestEvidence {
        try fixture.acquisition.saveRespondedRequest(
            observation: observation ?? rawObservation(),
            valueOutcome: valueOutcome,
            elapsedNanoseconds: elapsedNanoseconds,
            reasonCode: nil,
            requestOrdinal: 0,
            in: AcquisitionBatchIdentity(ordinal: 0),
            for: fixture.session.id
        )
    }

    /// test用の2PID完全manifestを生成します。
    ///
    /// 責務: batch requestが参照できる連続manifest PID集合を返します。
    /// - Returns: 2件の完全PID snapshotを持つmanifest。
    private func makeManifest() throws -> ConnectionSessionAcquisitionManifest {
        let requests = [
            OBDPIDRequest(service: 1, pid: 12),
            OBDPIDRequest(service: 1, pid: 13)
        ]
        let definitions = try requests.map { request in
            try AcquisitionPIDDefinitionSnapshot(
                request: request,
                capabilitySupport: .supported,
                isCollectionEnabled: true,
                definitionRevision: 1,
                requiredByteCount: request.pid == 12 ? 2 : 1,
                definitionIdentity: AcquisitionPIDDefinitionIdentity(
                    canonicalizationVersion: 1,
                    expression: "A"
                ),
                unit: "unit",
                validityRange: .notDeclared
            )
        }
        return try ConnectionSessionAcquisitionManifest(
            manifestVersion: 1,
            applicationVersion: AcquisitionApplicationVersion(marketingVersion: "1", buildVersion: "1"),
            schemaContractVersion: 1,
            pollingPolicyVersion: 1,
            orderedRequestedPIDs: OrderedAcquisitionPIDSet(requests: requests),
            pidDefinitions: definitions,
            acquisitionPlatform: .macOS,
            modelInputManifestVersion: 1
        )
    }

    /// 指定件数のselected-only requestを持つopen batchを生成します。
    ///
    /// 責務: policy評価完了済みで未送信のtest batchを返します。
    /// - Parameter requestCount: 先頭から選択するmanifest PID数。
    /// - Returns: 未確定batch証拠。
    private func makeOpenBatch(requestCount: Int) throws -> AcquisitionBatchEvidence {
        let requests = try (0..<requestCount).map {
            try pendingRequest(requestOrdinal: $0, manifestPIDOrdinal: $0)
        }
        return try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: 0),
            generation: 1,
            policyTick: 0,
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 10),
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: requests
        )
    }

    /// 指定terminal状態のbatchを生成します。
    ///
    /// 責務: open fixtureと同じidentityを持つterminal test batchを返します。
    /// - Parameters:
    ///   - state: batch terminal状態。
    ///   - failure: batch failure。
    ///   - requests: terminalまたはpartial request列。
    /// - Returns: terminal batch証拠。
    private func makeTerminalBatch(
        state: AcquisitionBatchCompletionState,
        failure: AcquisitionBatchFailure?,
        requests: [PIDRequestEvidence]
    ) throws -> AcquisitionBatchEvidence {
        try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: 0),
            generation: 1,
            policyTick: 0,
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 10),
            completionState: state,
            completedAt: Date(timeIntervalSince1970: 12),
            failure: failure,
            requests: requests
        )
    }

    /// test用selected-only requestを生成します。
    ///
    /// 責務: 指定位置の未送信request evidenceを返します。
    /// - Parameters:
    ///   - requestOrdinal: batch内要求順。
    ///   - manifestPIDOrdinal: manifest PID位置。
    /// - Returns: selected-only request evidence。
    private func pendingRequest(
        requestOrdinal: Int,
        manifestPIDOrdinal: Int
    ) throws -> PIDRequestEvidence {
        try PIDRequestEvidence(
            requestOrdinal: requestOrdinal,
            manifestPIDOrdinal: manifestPIDOrdinal,
            dispatchState: .selectedOnly,
            transportOutcome: nil,
            valueOutcome: .notEvaluated,
            rawSequence: nil,
            elapsedNanoseconds: nil,
            reasonCode: nil
        )
    }
}

/// batch repository testが共有するin-memory依存です。
private struct BatchRepositoryFixture {
    /// 全repositoryが共有するin-memory SQLite Queueです。
    let queue: DatabaseQueue
    /// sessionとRawの保存先です。
    let sessions: GRDBConnectionSessionRepository
    /// manifestとbatch evidenceの保存先です。
    let acquisition: GRDBConnectionSessionAcquisitionRepository
    /// 親接続sessionです。
    let session: ConnectionSession
}
