import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 取得チャンクのRaw連番・セッション・セグメント・時刻情報の検証失敗を、行を書かないことと併せて検証します。
final class GRDBConnectionSessionAcquisitionChunkRepositoryRawValidationTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = GRDBConnectionSessionAcquisitionChunkRepositoryFixture

    /// チャンク内で同じ連番が重複すると `.duplicateSequenceInChunk` で失敗します。
    ///
    /// 責務: チャンク内の連番重複を拒否し、1行も書かないことを確認します。
    func testDuplicateSequenceInChunkIsRejected() throws {
        let fixture = try Fixture()
        let chunk = fixture.chunk(raws: [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1), Fixture.raw(sequence: 0)])

        try fixture.assertCommitRejected(chunk, with: .duplicateSequenceInChunk)
    }

    /// 保存済み行と同じ連番を含むと `.sequenceAlreadyStored` で失敗します。
    ///
    /// 責務: 保存済みRawとの連番重複を拒否し、同じチャンクの重複しないRawも書かないことを確認します。
    func testSequenceAlreadyStoredIsRejected() throws {
        let fixture = try Fixture()
        try fixture.repository.commit(fixture.chunk(raws: [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1)]))
        let chunk = fixture.chunk(raws: [Fixture.raw(sequence: 2), Fixture.raw(sequence: 1)])

        try fixture.assertCommitRejected(chunk, with: .sequenceAlreadyStored)
        XCTAssertEqual(try fixture.sessions.entries(for: fixture.sessionID).map(\.sequence), [0, 1])
    }

    /// 存在しないセッションのチャンクは `.sessionNotFound` で失敗します。
    ///
    /// 責務: 保存されていないセッションへRawを書かないことを確認します。
    func testUnknownSessionIsRejected() throws {
        let fixture = try Fixture()
        let chunk = ConnectionSessionAcquisitionChunk(
            sessionID: ConnectionSessionID(),
            rawEntries: [Fixture.raw(sequence: 0)],
            batches: []
        )

        try fixture.assertCommitRejected(chunk, with: .sessionNotFound)
    }

    /// 終了済みセッションのチャンクは `.sessionEnded` で失敗します。
    ///
    /// 責務: 終了済みセッションへRawを書かないことを確認します。
    func testEndedSessionIsRejected() throws {
        let fixture = try Fixture()
        let endedSessionID = try fixture.makeEndedSession()
        let chunk = ConnectionSessionAcquisitionChunk(
            sessionID: endedSessionID,
            rawEntries: [Fixture.raw(sequence: 0)],
            batches: []
        )

        try fixture.assertCommitRejected(chunk, with: .sessionEnded)
    }

    /// 開始を保存していないセグメント番号を指すRawは `.segmentNotStarted` で失敗します。
    ///
    /// 責務: 開始済みセグメントのRawと混ざっていても、未開始セグメントのRawを含むチャンクを拒否します。
    func testRawInUnstartedSegmentIsRejected() throws {
        let fixture = try Fixture(startedSegmentOrdinals: [0])
        let chunk = fixture.chunk(raws: [Fixture.raw(sequence: 0, segment: 0), Fixture.raw(sequence: 1, segment: 1)])

        try fixture.assertCommitRejected(chunk, with: .segmentNotStarted)
    }

    /// 単調時計ナノ秒を持たないRawは `.rawTimingMissing` で失敗します。
    ///
    /// 責務: 単調時計の欠落したRawを含むチャンクを拒否し、1行も書かないことを確認します。
    func testRawWithoutMonotonicIsRejected() throws {
        let fixture = try Fixture()
        let chunk = fixture.chunk(raws: [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1, omitsMonotonic: true)])

        try fixture.assertCommitRejected(chunk, with: .rawTimingMissing)
    }

    /// セグメント番号を持たないRawは `.rawTimingMissing` で失敗します。
    ///
    /// 責務: セグメント番号の欠落したRawを含むチャンクを拒否し、1行も書かないことを確認します。
    func testRawWithoutSegmentIsRejected() throws {
        let fixture = try Fixture()
        let chunk = fixture.chunk(raws: [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1, segment: nil)])

        try fixture.assertCommitRejected(chunk, with: .rawTimingMissing)
    }
}
