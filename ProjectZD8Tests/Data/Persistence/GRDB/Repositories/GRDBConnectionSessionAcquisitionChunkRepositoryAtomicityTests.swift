import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 取得チャンクの後半で失敗したとき、そのチャンク全体が保存されないことを検証します。
final class GRDBConnectionSessionAcquisitionChunkRepositoryAtomicityTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = GRDBConnectionSessionAcquisitionChunkRepositoryFixture

    /// 2件目のbatch番号が保存済みと重複すると、そのチャンクのRawもbatchもrequestも残りません。
    ///
    /// 責務: Raw保存後のbatch検証失敗がチャンク全体をrollbackし、先に成功したチャンクの行は残すことを確認します。
    func testStoredBatchConflictInSecondBatchRollsBackWholeChunk() throws {
        let fixture = try Fixture()
        let earlierRaws = [Fixture.raw(sequence: 0)]
        let earlierBatch = try Fixture.terminalBatch(ordinal: 0, respondedSequence: 0)
        try fixture.repository.commit(fixture.chunk(raws: earlierRaws, batches: [earlierBatch]))
        let failing = fixture.chunk(
            raws: [Fixture.raw(sequence: 1), Fixture.raw(sequence: 2)],
            batches: [
                try Fixture.terminalBatch(ordinal: 1, respondedSequence: 1),
                try Fixture.terminalBatch(ordinal: 0, respondedSequence: 2)
            ]
        )

        try fixture.assertCommitRejected(failing, with: .batchAlreadyStored)

        XCTAssertEqual(try fixture.sessions.entries(for: fixture.sessionID), earlierRaws)
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.sessionID), [earlierBatch])
        XCTAssertEqual(try fixture.rowCounts(), Fixture.RowCounts(raws: 1, batches: 1, requests: 2))
    }

    /// 存在しないRaw連番を参照するrequestがあると、そのチャンクのRawも残りません。
    ///
    /// 責務: Raw保存後の参照検証失敗がチャンク全体をrollbackし、先に成功したチャンクの行は残すことを確認します。
    func testMissingRawReferenceRollsBackWholeChunk() throws {
        let fixture = try Fixture()
        let earlierRaws = [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1)]
        try fixture.repository.commit(fixture.chunk(raws: earlierRaws))
        let failing = fixture.chunk(
            raws: [Fixture.raw(sequence: 2), Fixture.raw(sequence: 3)],
            batches: [
                try Fixture.terminalBatch(ordinal: 0, respondedSequence: 2),
                try Fixture.terminalBatch(ordinal: 1, respondedSequence: 99)
            ]
        )

        try fixture.assertCommitRejected(failing, with: .rawReferenceMissing)

        XCTAssertEqual(try fixture.sessions.entries(for: fixture.sessionID), earlierRaws)
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.sessionID), [])
        XCTAssertEqual(try fixture.rowCounts(), Fixture.RowCounts(raws: 2, batches: 0, requests: 0))
    }

    /// 失敗したチャンクを捨てた後、同じ連番で正しいチャンクを保存できます。
    ///
    /// 責務: rollbackされたRaw連番が保存済み扱いで残らず、再送したチャンクが受け入れられることを確認します。
    func testRolledBackSequencesCanBeCommittedAgain() throws {
        let fixture = try Fixture()
        let raws = [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1)]
        let failing = fixture.chunk(raws: raws, batches: [try Fixture.terminalBatch(ordinal: 0, respondedSequence: 99)])
        try fixture.assertCommitRejected(failing, with: .rawReferenceMissing)

        try fixture.repository.commit(fixture.chunk(raws: raws))

        XCTAssertEqual(try fixture.sessions.entries(for: fixture.sessionID), raws)
    }
}
