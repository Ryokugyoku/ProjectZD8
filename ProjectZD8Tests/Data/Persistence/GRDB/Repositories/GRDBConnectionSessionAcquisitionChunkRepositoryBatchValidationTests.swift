import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 取得チャンクのbatch検証失敗を、行を書かないことと併せて検証します。
final class GRDBConnectionSessionAcquisitionChunkRepositoryBatchValidationTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = GRDBConnectionSessionAcquisitionChunkRepositoryFixture

    /// 終端状態でないbatchは `.batchNotTerminal` で失敗します。
    ///
    /// 責務: 未確定batchを含むチャンクを拒否し、同じチャンクのRawも書かないことを確認します。
    func testOpenBatchIsRejected() throws {
        let fixture = try Fixture()
        let chunk = fixture.chunk(raws: [Fixture.raw(sequence: 0)], batches: [try Fixture.openBatch(ordinal: 0)])

        try fixture.assertCommitRejected(chunk, with: .batchNotTerminal)
    }

    /// チャンク内でbatch番号が重複すると `.duplicateBatchInChunk` で失敗します。
    ///
    /// 責務: チャンク内のbatch番号重複を拒否し、1行も書かないことを確認します。
    func testDuplicateBatchInChunkIsRejected() throws {
        let fixture = try Fixture()
        let chunk = fixture.chunk(
            raws: [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1)],
            batches: [
                try Fixture.terminalBatch(ordinal: 0, respondedSequence: 0),
                try Fixture.terminalBatch(ordinal: 0, respondedSequence: 1)
            ]
        )

        try fixture.assertCommitRejected(chunk, with: .duplicateBatchInChunk)
    }

    /// 保存済みbatchと同じ番号のbatchは `.batchAlreadyStored` で失敗します。
    ///
    /// 責務: 保存済みbatch番号との重複を拒否し、1行も書かないことを確認します。
    func testBatchAlreadyStoredIsRejected() throws {
        let fixture = try Fixture()
        try fixture.repository.commit(
            fixture.chunk(raws: [Fixture.raw(sequence: 0)], batches: [try Fixture.terminalBatch(ordinal: 0, respondedSequence: 0)])
        )
        let chunk = fixture.chunk(
            raws: [Fixture.raw(sequence: 1)],
            batches: [try Fixture.terminalBatch(ordinal: 0, respondedSequence: 1)]
        )

        try fixture.assertCommitRejected(chunk, with: .batchAlreadyStored)
    }

    /// 確定manifestが無いセッションへbatchを保存すると `.acquisitionStartMissing` で失敗します。
    ///
    /// 責務: 取得開始の証跡が無いbatchを拒否し、同じチャンクのRawも書かないことを確認します。
    func testBatchWithoutSealedManifestIsRejected() throws {
        let fixture = try Fixture(savesManifest: false)
        let chunk = fixture.chunk(
            raws: [Fixture.raw(sequence: 0)],
            batches: [try Fixture.terminalBatch(ordinal: 0, respondedSequence: 0)]
        )

        try fixture.assertCommitRejected(chunk, with: .acquisitionStartMissing)
    }

    /// 確定manifestが無くてもRawだけのチャンクは保存できます。
    ///
    /// 責務: manifestの検査がbatchを含むチャンクだけに適用されることを確認します。
    func testRawOnlyChunkWithoutManifestSucceeds() throws {
        let fixture = try Fixture(savesManifest: false)
        let raws = [Fixture.raw(sequence: 0)]

        try fixture.repository.commit(fixture.chunk(raws: raws))

        XCTAssertEqual(try fixture.sessions.entries(for: fixture.sessionID), raws)
    }

    /// チャンクにも保存済み行にも無いRaw連番を参照するrequestは `.rawReferenceMissing` で失敗します。
    ///
    /// 責務: 存在しないRawへの参照を拒否し、同じチャンクのRawも書かないことを確認します。
    func testReferenceToMissingRawIsRejected() throws {
        let fixture = try Fixture()
        let chunk = fixture.chunk(
            raws: [Fixture.raw(sequence: 0)],
            batches: [try Fixture.terminalBatch(ordinal: 0, respondedSequence: 1)]
        )

        try fixture.assertCommitRejected(chunk, with: .rawReferenceMissing)
    }

    /// 同じチャンク内のRawを参照するrequestは保存できます。
    ///
    /// 責務: 参照先Rawが同じトランザクションで保存されるとき、参照検証を通過することを確認します。
    func testReferenceToRawInSameChunkSucceeds() throws {
        let fixture = try Fixture()
        let batch = try Fixture.terminalBatch(ordinal: 0, respondedSequence: 0)

        try fixture.repository.commit(fixture.chunk(raws: [Fixture.raw(sequence: 0)], batches: [batch]))

        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.sessionID), [batch])
        XCTAssertEqual(try fixture.rowCounts(), Fixture.RowCounts(raws: 1, batches: 1, requests: 2))
    }
}
