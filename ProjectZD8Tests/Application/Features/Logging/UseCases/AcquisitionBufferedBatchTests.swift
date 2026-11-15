import Foundation
import XCTest
@testable import ProjectZD8

/// 保存待ちbatchの記録順序・終端化・打切り・証拠化を検証します。
final class AcquisitionBufferedBatchTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Values = AcquisitionBufferTestValues

    /// 生成直後は未完了で、次に記録する要求は先頭、要求が無ければ無しです。
    ///
    /// 責務: 初期状態の終端判定と次の要求順を確認します。
    func testInitialStateIsOpenWithFirstRequestNext() throws {
        let batch = try Values.batch(0, manifestOrdinals: [3, 1])
        let empty = try Values.batch(1, manifestOrdinals: [])

        XCTAssertFalse(batch.isTerminal)
        XCTAssertEqual(batch.nextRequestOrdinal, 0)
        XCTAssertEqual(batch.requests.map(\.manifestPIDOrdinal), [3, 1])
        XCTAssertNil(empty.nextRequestOrdinal)
    }

    /// 要求は順番どおりにだけ記録でき、正応答はRawを伴い、非応答はRawを伴いません。
    ///
    /// 責務: 順序違い・正応答のRaw欠落・非応答のRaw付きを入力不正として拒否することを確認します。
    func testRecordRejectsOutOfOrderAndRawMismatch() throws {
        var batch = try Values.batch(0, manifestOrdinals: [0, 1])

        XCTAssertThrowsError(try Values.respond(&batch, 1))
        XCTAssertThrowsError(try batch.record(
            requestOrdinal: 0, transportOutcome: .responded, valueOutcome: .decodedValid,
            elapsedNanoseconds: 1, reasonCode: nil, raw: nil
        ))
        XCTAssertThrowsError(try batch.record(
            requestOrdinal: 0, transportOutcome: .timedOut, valueOutcome: .notEvaluated,
            elapsedNanoseconds: 1, reasonCode: nil, raw: Values.raw()
        ))
        try Values.respond(&batch, 0)
        XCTAssertEqual(batch.nextRequestOrdinal, 1)
        XCTAssertEqual(batch.raws.count, 1)
        XCTAssertEqual(batch.requests[0].rawIndex, 0)
    }

    /// 全要求が終わる前の完了は入力不正で、完了後は記録も再完了もできません。
    ///
    /// 責務: 完了の前提と、終端後の変更拒否を確認します。
    func testCompleteRequiresAllRequestsAndIsFinal() throws {
        var batch = try Values.batch(0, manifestOrdinals: [0, 1])
        try Values.respond(&batch, 0)

        XCTAssertThrowsError(try batch.complete(at: Values.date(12), classifier: Values.classifier))
        try Values.respond(&batch, 1)
        try batch.complete(at: Values.date(12), classifier: Values.classifier)

        XCTAssertTrue(batch.isTerminal)
        XCTAssertEqual(batch.completionState, .completed)
        XCTAssertNil(batch.failure)
        XCTAssertEqual(batch.completedAt, Values.date(12))
        XCTAssertThrowsError(try batch.complete(at: Values.date(13), classifier: Values.classifier))
        XCTAssertThrowsError(try Values.respond(&batch, 1))
    }

    /// 非応答を含む完了は失敗として確定し、開始より前の完了日時は開始日時に揃えます。
    ///
    /// 責務: 分類部品のbatch失敗を反映し、完了日時が開始日時を下回らないことを確認します。
    func testCompleteWithFailureSealsAsFailedAndClampsCompletedAt() throws {
        var batch = try Values.batch(0, startedAt: 10)
        try Values.fail(&batch, 0, .timedOut)

        try batch.complete(at: Values.date(5), classifier: Values.classifier)

        XCTAssertEqual(batch.completionState, .failed)
        XCTAssertEqual(batch.failure, .transportUnavailable)
        XCTAssertEqual(batch.completedAt, Values.date(10))
    }

    /// 打切りは、全要求が終わっていれば通常の完了、途中なら取消の失敗、終端済みなら何もしません。
    ///
    /// 責務: 打切りの3つの分岐を確認します。
    func testAbandonSealsByProgress() throws {
        var finished = try Values.batch(0)
        try Values.respond(&finished, 0)
        finished.abandon(at: Values.date(12), classifier: Values.classifier)
        var partial = try Values.batch(1, manifestOrdinals: [0, 1])
        try Values.respond(&partial, 0)
        partial.abandon(at: Values.date(12), classifier: Values.classifier)
        var terminal = try Values.completedBatch(2, raws: [Values.raw()], completedAt: 12)
        terminal.abandon(at: Values.date(99), classifier: Values.classifier)

        XCTAssertEqual(finished.completionState, .completed)
        XCTAssertEqual(partial.completionState, .failed)
        XCTAssertEqual(partial.failure, .cancelled)
        XCTAssertEqual(terminal.completedAt, Values.date(12))
    }

    /// 証拠化は終端済みのbatchだけで行い、Rawへ先頭連番から順に番号を振り、要求から参照します。
    ///
    /// 責務: 未完了の証拠化の拒否、Rawの連番・時刻情報、要求の送信状態・参照・分類を確認します。
    func testEvidenceNumbersRawsFromFirstSequence() throws {
        var batch = try Values.batch(4, manifestOrdinals: [0, 1, 2])
        XCTAssertThrowsError(try batch.evidence(firstSequence: 0))
        try Values.respond(&batch, 0, raw: Values.raw(observedAt: 11, payload: [7]))
        try Values.fail(&batch, 1, .timedOut)
        batch.abandon(at: Values.date(13), classifier: Values.classifier)

        let built = try batch.evidence(firstSequence: 20)

        XCTAssertEqual(built.rawEntries.map(\.sequence), [20])
        XCTAssertEqual(built.rawEntries.map(\.payload), [[7]])
        XCTAssertEqual(built.batch.identity.ordinal, 4)
        XCTAssertEqual(built.batch.policyTick, 4)
        XCTAssertEqual(built.batch.requests.map(\.rawSequence), [20, nil, nil])
        XCTAssertEqual(built.batch.requests.map(\.dispatchState), [.terminal, .terminal, .selectedOnly])
        XCTAssertEqual(built.batch.requests.map(\.transportOutcome), [.responded, .timedOut, nil])
        XCTAssertEqual(built.batch.requests.map(\.manifestPIDOrdinal), [0, 1, 2])
        XCTAssertEqual(built.batch.completionState, .failed)
    }
}
