import XCTest
@testable import ProjectZD8

/// batch、selection、request outcomeのDomain不変条件を検証します。
final class AcquisitionBatchEvidenceTests: XCTestCase {
    /// policy評価完了時だけ非選択PIDを意図的省略として返します。
    ///
    /// 責務: 選択集合差が未完了batchやmissing値から推測されないことを確認します。
    func testIntentionalOmissionRequiresCompletedPolicyEvaluation() throws {
        let request = try pendingRequest(requestOrdinal: 0, manifestPIDOrdinal: 1)
        let completed = try batch(selectionComplete: true, requests: [request])
        let incomplete = try batch(selectionComplete: false, requests: [request])

        XCTAssertEqual(completed.selection(for: 1), .requested)
        XCTAssertEqual(completed.selection(for: 0), .intentionalPollingOmission)
        XCTAssertNil(incomplete.selection(for: 0))
    }

    /// respondedだけがRaw sequenceを参照できます。
    ///
    /// 責務: response有無とRaw参照の双方向不変条件を確認します。
    func testRawReferenceExistsOnlyForRespondedRequest() throws {
        XCTAssertThrowsError(try terminalRequest(outcome: .responded, rawSequence: nil)) {
            XCTAssertEqual($0 as? AcquisitionBatchEvidenceError, .respondedRawReferenceMissing)
        }
        XCTAssertThrowsError(try terminalRequest(outcome: .timedOut, rawSequence: 4)) {
            XCTAssertEqual($0 as? AcquisitionBatchEvidenceError, .nonResponseContainsValue)
        }
        XCTAssertNoThrow(try terminalRequest(outcome: .responded, rawSequence: 4))
    }

    /// 明示cancelとprocess終了後unknownを別値として保持します。
    ///
    /// 責務: 2種類のterminal transport outcomeがDomain上で混同されないことを確認します。
    func testCancellationAndUnknownAfterTerminationRemainDistinct() throws {
        let cancelled = try terminalRequest(outcome: .cancelled, rawSequence: nil)
        let terminated = try terminalRequest(outcome: .unknownAfterTermination, rawSequence: nil)

        XCTAssertEqual(cancelled.transportOutcome, .cancelled)
        XCTAssertEqual(terminated.transportOutcome, .unknownAfterTermination)
        XCTAssertNotEqual(cancelled, terminated)
    }

    /// completed batchは全要求のterminal結果を必要とします。
    ///
    /// 責務: selected-only要求を含むbatchが完全成功へ確定されないことを確認します。
    func testCompletedBatchRejectsPartialRequest() throws {
        let request = try pendingRequest(requestOrdinal: 0, manifestPIDOrdinal: 0)

        XCTAssertThrowsError(
            try AcquisitionBatchEvidence(
                identity: AcquisitionBatchIdentity(ordinal: 0),
                generation: 1,
                policyTick: 0,
                isSelectionEvaluationComplete: true,
                startedAt: Date(timeIntervalSince1970: 10),
                completionState: .completed,
                completedAt: Date(timeIntervalSince1970: 11),
                failure: nil,
                requests: [request]
            )
        ) {
            XCTAssertEqual($0 as? AcquisitionBatchEvidenceError, .invalidBatchState)
        }
    }

    /// test用未確定batchを生成します。
    ///
    /// 責務: selection完了状態と要求列を固定したopen batchを返します。
    /// - Parameters:
    ///   - selectionComplete: policy評価完了の有無。
    ///   - requests: 選択済み要求列。
    /// - Returns: terminal結果を持たないbatch証拠。
    private func batch(
        selectionComplete: Bool,
        requests: [PIDRequestEvidence]
    ) throws -> AcquisitionBatchEvidence {
        try AcquisitionBatchEvidence(
            identity: AcquisitionBatchIdentity(ordinal: 0),
            generation: 1,
            policyTick: 0,
            isSelectionEvaluationComplete: selectionComplete,
            startedAt: Date(timeIntervalSince1970: 10),
            completionState: nil,
            completedAt: nil,
            failure: nil,
            requests: requests
        )
    }

    /// test用selected-only要求を生成します。
    ///
    /// 責務: 指定ordinalを持つ値未評価の要求証拠を返します。
    /// - Parameters:
    ///   - requestOrdinal: batch内要求順。
    ///   - manifestPIDOrdinal: manifest PID位置。
    /// - Returns: dispatch前の要求証拠。
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

    /// test用terminal要求を生成します。
    ///
    /// 責務: 指定transport outcomeとRaw参照を持つ要求証拠を返します。
    /// - Parameters:
    ///   - outcome: terminal transport outcome。
    ///   - rawSequence: 既存Raw参照候補。
    /// - Returns: terminal要求証拠。
    private func terminalRequest(
        outcome: PIDRequestTransportOutcome,
        rawSequence: Int64?
    ) throws -> PIDRequestEvidence {
        try PIDRequestEvidence(
            requestOrdinal: 0,
            manifestPIDOrdinal: 0,
            dispatchState: .terminal,
            transportOutcome: outcome,
            valueOutcome: outcome == .responded ? .decodedValid : .notEvaluated,
            rawSequence: rawSequence,
            elapsedNanoseconds: 100,
            reasonCode: nil
        )
    }
}
