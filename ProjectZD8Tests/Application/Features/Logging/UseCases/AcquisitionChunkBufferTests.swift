import Foundation
import XCTest
@testable import ProjectZD8

/// 保存待ちバッファが終端済みbatchだけをチャンクに組み立て、連番を割り当て、commit結果を反映することを検証します。
final class AcquisitionChunkBufferTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Values = AcquisitionBufferTestValues

    /// 最後にcommitした連番は、次の連番が0なら無し、それ以外は1つ前です。
    ///
    /// 責務: 初期状態の件数・未完了batch・最終連番を確認します。
    func testInitialState() {
        XCTAssertNil(AcquisitionChunkBuffer(nextSequence: 0).lastCommittedSequence)
        XCTAssertEqual(AcquisitionChunkBuffer(nextSequence: 5).lastCommittedSequence, 4)
        XCTAssertEqual(AcquisitionChunkBuffer(nextSequence: 5).bufferedRawCount, 0)
        XCTAssertNil(AcquisitionChunkBuffer(nextSequence: 0).openBatch)
    }

    /// 未完了batchがある間は次のbatchを始められず、終端後は始められます。
    ///
    /// 責務: 未完了batchの二重開始の拒否と、終端後の開始を確認します。
    func testBeginRequiresNoOpenBatch() throws {
        var buffer = AcquisitionChunkBuffer(nextSequence: 0)
        try buffer.begin(try Values.batch(0))

        XCTAssertEqual(buffer.openBatch?.identity.ordinal, 0)
        XCTAssertThrowsError(try buffer.begin(try Values.batch(1)))
        try buffer.updateOpenBatch(ordinal: 0) { try Values.respond(&$0, 0) }
        try buffer.updateOpenBatch(ordinal: 0) { try $0.complete(at: Values.date(12), classifier: Values.classifier) }
        XCTAssertNil(buffer.openBatch)
        XCTAssertNoThrow(try buffer.begin(try Values.batch(1)))
    }

    /// 未完了batchの更新は、batchが無い・番号違い・終端済みのいずれでも入力不正です。
    ///
    /// 責務: 更新対象の検証の3つの分岐を確認します。
    func testUpdateOpenBatchRejectsMissingWrongOrTerminal() throws {
        var buffer = AcquisitionChunkBuffer(nextSequence: 0)
        XCTAssertThrowsError(try buffer.updateOpenBatch(ordinal: 0) { _ in })
        try buffer.begin(try Values.batch(0))
        XCTAssertThrowsError(try buffer.updateOpenBatch(ordinal: 1) { _ in })
        try buffer.updateOpenBatch(ordinal: 0) { try Values.respond(&$0, 0) }
        try buffer.updateOpenBatch(ordinal: 0) { try $0.complete(at: Values.date(12), classifier: Values.classifier) }

        XCTAssertThrowsError(try buffer.updateOpenBatch(ordinal: 0) { _ in })
        XCTAssertEqual(buffer.bufferedRawCount, 1)
    }

    /// 終端済みbatchが無ければチャンクは無く、先頭から連続する終端済みbatchだけがチャンクに入ります。
    ///
    /// 責務: 未完了batchを持ち越し、Rawへ受信順に次の連番から番号を振ることを確認します。
    func testPendingChunkTakesLeadingTerminalBatchesWithSequentialNumbers() throws {
        let sessionID = ConnectionSessionID()
        var buffer = AcquisitionChunkBuffer(nextSequence: 7)
        try buffer.begin(try Values.batch(0))
        XCTAssertNil(try buffer.pendingChunk(sessionID: sessionID))
        try buffer.updateOpenBatch(ordinal: 0) { try Values.respond(&$0, 0, raw: Values.raw(payload: [1])) }
        try buffer.updateOpenBatch(ordinal: 0) { try $0.complete(at: Values.date(12), classifier: Values.classifier) }
        try buffer.begin(try Values.completedBatch(1, raws: [Values.raw(payload: [2]), Values.raw(payload: [3])]))
        try buffer.begin(try Values.batch(2))
        try buffer.updateOpenBatch(ordinal: 2) { try Values.respond(&$0, 0, raw: Values.raw(payload: [4])) }

        let pending = try XCTUnwrap(try buffer.pendingChunk(sessionID: sessionID))

        XCTAssertEqual(pending.chunk.sessionID, sessionID)
        XCTAssertEqual(pending.chunk.batches.map(\.identity.ordinal), [0, 1])
        XCTAssertEqual(pending.chunk.rawEntries.map(\.sequence), [7, 8, 9])
        XCTAssertEqual(pending.chunk.rawEntries.map(\.payload), [[1], [2], [3]])
        XCTAssertEqual(pending.chunk.batches[1].requests.map(\.rawSequence), [8, 9])
        XCTAssertEqual(pending.batchCount, 2)
        XCTAssertEqual(pending.nextSequenceAfterCommit, 10)
        XCTAssertEqual(buffer.bufferedRawCount, 4)
    }

    /// チャンクの最初と最後の実時刻は、batch開始・Raw観測・batch完了の最小と最大です。
    ///
    /// 責務: 時刻の範囲と、Rawの最初・最後の区間番号、Rawが無い場合の区間番号を確認します。
    func testPendingChunkTimeSpanAndSegments() throws {
        var buffer = AcquisitionChunkBuffer(nextSequence: 0)
        try buffer.begin(try Values.completedBatch(0, raws: [Values.raw(observedAt: 9, segment: 1), Values.raw(observedAt: 14, segment: 2)], completedAt: 13))
        var empty = AcquisitionChunkBuffer(nextSequence: 0)
        var timedOut = try Values.batch(0, startedAt: 20)
        try Values.fail(&timedOut, 0, .timedOut)
        try timedOut.complete(at: Values.date(21), classifier: Values.classifier)
        try empty.begin(timedOut)

        let pending = try XCTUnwrap(try buffer.pendingChunk(sessionID: ConnectionSessionID()))
        let withoutRaw = try XCTUnwrap(try empty.pendingChunk(sessionID: ConnectionSessionID()))

        XCTAssertEqual(pending.firstObservedAt, Values.date(9))
        XCTAssertEqual(pending.lastObservedAt, Values.date(14))
        XCTAssertEqual(pending.firstSegmentOrdinal, 1)
        XCTAssertEqual(pending.lastSegmentOrdinal, 2)
        XCTAssertEqual(withoutRaw.firstObservedAt, Values.date(20))
        XCTAssertEqual(withoutRaw.lastObservedAt, Values.date(21))
        XCTAssertNil(withoutRaw.firstSegmentOrdinal)
        XCTAssertNil(withoutRaw.lastSegmentOrdinal)
    }

    /// commit成功は連番を進めてbatchを除き、破棄は連番を進めずにbatchだけを除きます。
    ///
    /// 責務: 成功時の連番の前進と、失敗チャンクの番号を次のチャンクで再利用することを確認します。
    func testRemoveCommittedAdvancesAndRemoveDiscardedReusesSequences() throws {
        let sessionID = ConnectionSessionID()
        var buffer = AcquisitionChunkBuffer(nextSequence: 0)
        try buffer.begin(try Values.completedBatch(0, raws: [Values.raw()]))
        let first = try XCTUnwrap(try buffer.pendingChunk(sessionID: sessionID))
        buffer.removeCommitted(first)
        try buffer.begin(try Values.completedBatch(1, raws: [Values.raw(), Values.raw()]))
        let discarded = try XCTUnwrap(try buffer.pendingChunk(sessionID: sessionID))
        buffer.removeDiscarded(discarded)
        try buffer.begin(try Values.completedBatch(2, raws: [Values.raw()]))

        let next = try XCTUnwrap(try buffer.pendingChunk(sessionID: sessionID))

        XCTAssertEqual(buffer.lastCommittedSequence, 0)
        XCTAssertEqual(discarded.chunk.rawEntries.map(\.sequence), [1, 2])
        XCTAssertEqual(next.chunk.rawEntries.map(\.sequence), [1])
        XCTAssertEqual(next.chunk.batches.map(\.identity.ordinal), [2])
    }

    /// 未完了batchの打切りは最後のbatchを終端させ、batchが無ければ何もしません。
    ///
    /// 責務: 打切り後に最後のbatchがチャンクへ入ることと、空のバッファで安全なことを確認します。
    func testAbandonOpenBatchSealsLastBatch() throws {
        var empty = AcquisitionChunkBuffer(nextSequence: 0)
        empty.abandonOpenBatch(at: Values.date(12), classifier: Values.classifier)
        var buffer = AcquisitionChunkBuffer(nextSequence: 0)
        try buffer.begin(try Values.batch(0, manifestOrdinals: [0, 1]))
        try buffer.updateOpenBatch(ordinal: 0) { try Values.respond(&$0, 0) }

        buffer.abandonOpenBatch(at: Values.date(12), classifier: Values.classifier)

        XCTAssertEqual(empty.batches, [])
        XCTAssertNil(buffer.openBatch)
        XCTAssertEqual(try buffer.pendingChunk(sessionID: ConnectionSessionID())?.chunk.batches.first?.failure, .cancelled)
    }
}
