import Foundation
import XCTest
@testable import ProjectZD8

/// プロセス終了後に開いたままのbatchを回復するApplication処理を検証します。
@MainActor
final class PersistAcquisitionBatchUseCaseTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = GRDBConnectionSessionAcquisitionChunkRepositoryFixture

    /// 送信開始済みの要求だけを終了後不明へ遷移させ、未送信の要求は選択のみのまま残します。
    ///
    /// 責務: 明示取消と異なる終了後不明を選択のみの要求と共存させ、batchを終了不明で確定することを確認します。
    func testTerminationRecoveryKeepsUnknownDistinctFromCancellation() async throws {
        let fixture = try Fixture()
        let identity = try AcquisitionBatchIdentity(ordinal: 0)
        try fixture.acquisition.beginBatch(try openBatch(identity: identity), for: fixture.sessionID)
        try fixture.acquisition.markRequestDispatchBegun(requestOrdinal: 0, in: identity, for: fixture.sessionID)
        let useCase = PersistAcquisitionBatchUseCase(repository: fixture.acquisition)

        let result = try await useCase.recoverAfterTermination(
            batchIdentity: identity,
            for: fixture.sessionID,
            completedAt: Date(timeIntervalSince1970: 30)
        )

        XCTAssertEqual(result.requests[0].transportOutcome, .unknownAfterTermination)
        XCTAssertNotEqual(result.requests[0].transportOutcome, .cancelled)
        XCTAssertNil(result.requests[0].elapsedNanoseconds)
        XCTAssertEqual(result.requests[0].reasonCode, "process_terminated_after_dispatch")
        XCTAssertEqual(result.requests[1].dispatchState, .selectedOnly)
        XCTAssertEqual(result.completionState, .terminatedUnknown)
        XCTAssertEqual(result.failure, .processTerminated)
        XCTAssertEqual(result.completedAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.sessionID), [result])
    }

    /// 開いたbatchが無ければ入力不正として失敗します。
    ///
    /// 責務: 保存済みでないbatchの回復を成功扱いしないことを確認します。
    func testRecoveryWithoutOpenBatchThrowsInvalidInput() async throws {
        let fixture = try Fixture()
        let useCase = PersistAcquisitionBatchUseCase(repository: fixture.acquisition)

        do {
            _ = try await useCase.recoverAfterTermination(
                batchIdentity: try AcquisitionBatchIdentity(ordinal: 3),
                for: fixture.sessionID,
                completedAt: Date(timeIntervalSince1970: 30)
            )
            XCTFail("開いたbatchが無いのに回復が成功しました")
        } catch {
            XCTAssertEqual(error as? PersistAcquisitionBatchError, .invalidInput)
        }
    }

    /// 保存先が使えなければ永続化失敗として失敗します。
    ///
    /// 責務: Repositoryの失敗を回復の成功や入力不正に潰さないことを確認します。
    func testRepositoryFailureThrowsPersistenceFailure() async throws {
        let useCase = PersistAcquisitionBatchUseCase(repository: UnavailableConnectionSessionRepository())

        do {
            _ = try await useCase.recoverAfterTermination(
                batchIdentity: try AcquisitionBatchIdentity(ordinal: 0),
                for: ConnectionSessionID(),
                completedAt: Date(timeIntervalSince1970: 30)
            )
            XCTFail("保存先が使えないのに回復が成功しました")
        } catch {
            XCTAssertEqual(error as? PersistAcquisitionBatchError, .persistenceFailure)
        }
    }

    /// 2要求を選択済みにした開いたbatchを生成します。
    ///
    /// 責務: 回復の前提になる、終端していないbatch証拠を返します。
    /// - Parameter identity: batch番号。
    /// - Returns: 開いたbatch証拠。
    /// - Throws: batch証拠の不変条件違反。
    private func openBatch(identity: AcquisitionBatchIdentity) throws -> AcquisitionBatchEvidence {
        try AcquisitionBatchEvidence(
            identity: identity,
            generation: 1,
            policyTick: 0,
            isSelectionEvaluationComplete: true,
            startedAt: Date(timeIntervalSince1970: 10),
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: try (0..<2).map { ordinal in
                try PIDRequestEvidence(
                    requestOrdinal: ordinal, manifestPIDOrdinal: ordinal, dispatchState: .selectedOnly,
                    transportOutcome: nil, valueOutcome: .notEvaluated, rawSequence: nil,
                    elapsedNanoseconds: nil, reasonCode: nil
                )
            }
        )
    }
}
