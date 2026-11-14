import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// 取得チャンクの成功時の保存内容、連続チャンク、空チャンクを検証します。
final class GRDBConnectionSessionAcquisitionChunkRepositoryTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = GRDBConnectionSessionAcquisitionChunkRepositoryFixture

    /// Raw複数件とresponded/non-responded requestを含むbatchを1チャンクで保存して読み戻せます。
    ///
    /// 責務: Rawの全項目とbatch・requestの全件が、渡した値のまま保存されることを確認します。
    func testCommitStoresRawsBatchesAndRequestsAsGiven() throws {
        let fixture = try Fixture(startedSegmentOrdinals: [0, 1])
        let raws = [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1), Fixture.raw(sequence: 2, segment: 1)]
        let batches = [
            try Fixture.terminalBatch(ordinal: 0, respondedSequence: 0),
            try Fixture.terminalBatch(ordinal: 1, respondedSequence: 2)
        ]

        try fixture.repository.commit(fixture.chunk(raws: raws, batches: batches))

        let stored = try fixture.sessions.entries(for: fixture.sessionID)
        XCTAssertEqual(stored, raws)
        XCTAssertEqual(stored.map(\.monotonicNanoseconds), [7_000_000_000, 7_000_001_000, 7_000_002_000])
        XCTAssertEqual(stored.map(\.segmentOrdinal), [0, 0, 1])
        XCTAssertEqual(stored.map(\.observedAt), [100, 101, 102].map { Date(timeIntervalSince1970: $0) })
        XCTAssertEqual(stored.map(\.payload), [[0x00, 0x40], [0x01, 0x40], [0x02, 0x40]])
        let storedBatches = try fixture.acquisition.batches(for: fixture.sessionID)
        XCTAssertEqual(storedBatches, batches)
        XCTAssertEqual(storedBatches.flatMap(\.requests).map(\.transportOutcome), [.responded, .timedOut, .responded, .timedOut])
        XCTAssertEqual(storedBatches.flatMap(\.requests).map(\.rawSequence), [0, nil, 2, nil])
        XCTAssertEqual(try fixture.rowCounts(), Fixture.RowCounts(raws: 3, batches: 2, requests: 4))
    }

    /// 連番を続けた2つのチャンクを保存すると、全件が欠番も重複もなく読めます。
    ///
    /// 責務: チャンク境界をまたいでもRawの連番が渡した順に連続して保存されることを確認します。
    func testConsecutiveChunksStoreContiguousSequences() throws {
        let fixture = try Fixture()
        let first = [Fixture.raw(sequence: 0), Fixture.raw(sequence: 1), Fixture.raw(sequence: 2)]
        let second = [Fixture.raw(sequence: 3), Fixture.raw(sequence: 4)]

        try fixture.repository.commit(fixture.chunk(raws: first))
        try fixture.repository.commit(fixture.chunk(raws: second))

        let stored = try fixture.sessions.entries(for: fixture.sessionID)
        XCTAssertEqual(stored.map(\.sequence), [0, 1, 2, 3, 4])
        XCTAssertEqual(stored, first + second)
    }

    /// 前のチャンクで保存済みのRawを参照するrequestを保存できます。
    ///
    /// 責務: responded requestの参照先がチャンク内に無くても保存済み行にあれば受け入れることを確認します。
    func testBatchReferencingRawFromEarlierChunkSucceeds() throws {
        let fixture = try Fixture()
        try fixture.repository.commit(fixture.chunk(raws: [Fixture.raw(sequence: 0)]))
        let batch = try Fixture.terminalBatch(ordinal: 0, respondedSequence: 0)

        try fixture.repository.commit(fixture.chunk(raws: [], batches: [batch]))

        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.sessionID), [batch])
        XCTAssertEqual(try fixture.rowCounts(), Fixture.RowCounts(raws: 1, batches: 1, requests: 2))
    }

    /// 空チャンクは何も書かずに正常終了します。
    ///
    /// 責務: Rawもbatchも無いチャンクが例外を投げず、どの表の行数も変えないことを確認します。
    func testEmptyChunkWritesNothingAndSucceeds() throws {
        let fixture = try Fixture()
        let before = try fixture.rowCounts()

        XCTAssertNoThrow(try fixture.repository.commit(fixture.chunk(raws: [])))

        XCTAssertEqual(try fixture.rowCounts(), before)
        XCTAssertEqual(before, Fixture.RowCounts(raws: 0, batches: 0, requests: 0))
    }
}
