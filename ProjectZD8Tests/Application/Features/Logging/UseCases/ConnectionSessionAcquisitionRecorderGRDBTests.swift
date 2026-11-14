import Foundation
import GRDB
import XCTest
@testable import ProjectZD8

/// メモリ上のGRDBへ、取得記録がチャンク・欠損・区間を保存する主要経路を検証します。
@MainActor
final class ConnectionSessionAcquisitionRecorderGRDBTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture

    /// 開始でmanifestと開始理由 initial の区間がDBへ保存されます。
    ///
    /// 責務: manifestの要求順と区間1件がGRDBへ保存されることを確認します。
    func testStartPersistsManifestAndInitialSegment() async throws {
        let fixture = try Fixture(storage: .grdb)

        try await fixture.start()

        let manifest = try XCTUnwrap(fixture.acquisition.manifest(for: fixture.sessionID))
        XCTAssertEqual(manifest.orderedRequestedPIDs?.requests, [0x0C, 0x0D].map { OBDPIDRequest(service: 0x01, pid: $0) })
        let segments = try fixture.segments.segments(for: fixture.sessionID)
        XCTAssertEqual(segments.map(\.segmentOrdinal), [0])
        XCTAssertEqual(segments.map(\.startReason), [.initial])
        XCTAssertEqual(segments.map(\.firstSequence), [0])
    }

    /// commitに失敗したチャンクはDBに1行も残らず、bufferOverflow の欠損が1件保存され、次のチャンクは保存されます。
    ///
    /// 責務: 失敗前後の行数、欠損の内容、保存済みRawの連番に重複も欠番も無いこと、失敗チャンクのRawが後から現れないことを確認します。
    func testFailedChunkLeavesNoRowsAndLaterChunksStayContiguous() async throws {
        let fixture = try Fixture(storage: .grdb, failingCommits: [1])
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 10)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        let before = try rowCounts(fixture.queue)
        fixture.dates.set(Date(timeIntervalSince1970: 1_100))
        try await fixture.beginRound(1, pids: [0x0C, 0x0D])
        try await fixture.record(1, 0, .responded([20]))
        try await fixture.record(1, 1, pid: 0x0D, .responded([21]))
        fixture.dates.set(Date(timeIntervalSince1970: 1_101))
        try await fixture.finishRound(1)

        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        XCTAssertEqual(try rowCounts(fixture.queue), before)
        let gaps = try fixture.gaps.gaps(for: fixture.sessionID)
        XCTAssertEqual(gaps.map(\.cause), [.bufferOverflow])
        XCTAssertEqual(gaps.first?.startedAt, Date(timeIntervalSince1970: 1_100))
        XCTAssertEqual(gaps.first?.endedAt, Date(timeIntervalSince1970: 1_101))
        try await fixture.respondedRound(2, payload: 30)
        try await fixture.respondedRound(3, payload: 40)
        try await fixture.recorder.finish(generation: 1, reason: .userDisconnected)
        let raws = try fixture.storedRaws()
        XCTAssertEqual(raws.map(\.payload), [[10], [30], [40]])
        XCTAssertEqual(raws.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(Set(raws.map(\.sequence)).count, raws.count)
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.sessionID).map(\.identity.ordinal), [0, 2, 3])
        XCTAssertEqual(try fixture.segments.segments(for: fixture.sessionID).first?.lastSequence, 2)
    }

    /// 失敗が無ければ、複数チャンクにまたがっても連番は0から欠番も重複もなく続きます。
    ///
    /// 責務: 周回ごとにRaw件数が異なるチャンクを3回保存し、連番と要求からの参照を確認します。
    func testSequencesAreContiguousAcrossChunksWithoutFailures() async throws {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        for ordinal in Int64(0)..<3 {
            try await fixture.beginRound(ordinal, pids: [0x0C, 0x0D])
            try await fixture.record(ordinal, 0, .responded([UInt8(ordinal)]))
            try await fixture.record(ordinal, 1, pid: 0x0D, ordinal == 1 ? .timedOut : .responded([UInt8(ordinal + 100)]))
            try await fixture.finishRound(ordinal)
            try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        }

        let raws = try fixture.storedRaws()
        XCTAssertEqual(raws.map(\.sequence), [0, 1, 2, 3, 4])
        let references = try fixture.acquisition.batches(for: fixture.sessionID).flatMap(\.requests).compactMap(\.rawSequence)
        XCTAssertEqual(references, [0, 1, 2, 3, 4])
        XCTAssertEqual(fixture.chunks.committed.count, 3)
    }

    /// 各Rawに実時刻・単調時計・連番・区間番号が付き、単調時計が戻っても保存値は区間内で減りません。
    ///
    /// 責務: 単調時計を進め・戻し・進めて記録し、保存された単調時計が前回値に揃えられることを確認します。
    func testRawsCarryTimingAndMonotonicNeverDecreases() async throws {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        try await fixture.beginRound(0, pids: [0x0C, 0x0D])
        fixture.clock.set(nanoseconds: 9_000)
        fixture.dates.set(Date(timeIntervalSince1970: 1_001))
        try await fixture.record(0, 0, .responded([1]))
        fixture.clock.set(nanoseconds: 6_000)
        fixture.dates.set(Date(timeIntervalSince1970: 1_002))
        try await fixture.record(0, 1, pid: 0x0D, .responded([2]))
        try await fixture.finishRound(0)
        try await fixture.beginRound(1)
        fixture.clock.set(nanoseconds: 12_000)
        try await fixture.record(1, 0, .responded([3]))
        try await fixture.finishRound(1)

        try await fixture.recorder.flush(.sessionEnded, generation: 1)

        let raws = try fixture.storedRaws()
        XCTAssertEqual(raws.map(\.monotonicNanoseconds), [9_000, 9_000, 12_000])
        XCTAssertEqual(raws.map(\.observedAt), [1_001, 1_002, 1_002].map { Date(timeIntervalSince1970: $0) })
        XCTAssertEqual(raws.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(raws.map(\.segmentOrdinal), [0, 0, 0])
        XCTAssertEqual(raws.map(\.pid), [0x0C, 0x0D, 0x0C])
    }

    /// 終端済みの周回だけがチャンクに入り、未完了の周回は次のチャンクへ持ち越され、要求が参照するRawはcommit済みです。
    ///
    /// 責務: 未完了の周回のRawが先に保存されず、完了後に参照付きで保存されることを確認します。
    func testOpenRoundIsCarriedOverToNextChunk() async throws {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 1)
        try await fixture.beginRound(1, pids: [0x0C, 0x0D])
        try await fixture.record(1, 0, .responded([2]))

        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        XCTAssertEqual(try fixture.storedRaws().map(\.payload), [[1]])
        XCTAssertEqual(try fixture.acquisition.batches(for: fixture.sessionID).map(\.identity.ordinal), [0])
        try await fixture.record(1, 1, pid: 0x0D, .responded([3]))
        try await fixture.finishRound(1)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        let raws = try fixture.storedRaws()
        XCTAssertEqual(raws.map(\.payload), [[1], [2], [3]])
        let round = try XCTUnwrap(fixture.acquisition.batches(for: fixture.sessionID).last)
        XCTAssertEqual(round.identity.ordinal, 1)
        XCTAssertEqual(round.requests.map(\.rawSequence), [1, 2])
        XCTAssertTrue(round.requests.compactMap(\.rawSequence).allSatisfy(Set(raws.map(\.sequence)).contains))
    }

    /// タイムアウトはRawを作らず、失敗で確定したbatchだけを保存し、値の評価は未評価に揃えます。
    ///
    /// 責務: 非応答の要求の分類・理由コード・参照なし・値の評価と、batchの失敗理由を確認します。
    func testTimeoutStoresSealedFailedBatchWithoutRaw() async throws {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        try await fixture.beginRound(0)
        try await fixture.record(0, 0, .timedOut, valueOutcome: .decodedValid)
        try await fixture.finishRound(0)

        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        XCTAssertEqual(try fixture.storedRaws(), [])
        let batch = try XCTUnwrap(fixture.acquisition.batches(for: fixture.sessionID).first)
        XCTAssertEqual(batch.completionState, .failed)
        XCTAssertEqual(batch.failure, .transportUnavailable)
        XCTAssertEqual(batch.requests.map(\.transportOutcome), [.timedOut])
        XCTAssertEqual(batch.requests.map(\.reasonCode), ["response_timeout"])
        XCTAssertEqual(batch.requests.map(\.rawSequence), [nil])
        XCTAssertEqual(batch.requests.map(\.valueOutcome), [.notEvaluated])
    }

    /// 正応答の値の評価と、間引いた周回のmanifest内の位置がそのまま保存されます。
    ///
    /// 責務: デコード失敗・不正値でもRawを残し、周回内の要求順とmanifest順の違いを保持し、明示非対応を失敗にしないことを確認します。
    func testValueOutcomesAndManifestOrdinalsArePersisted() async throws {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        try await fixture.beginRound(0, pids: [0x0D])
        try await fixture.record(0, 0, pid: 0x0D, .responded([1]), valueOutcome: .decodeFailure)
        try await fixture.finishRound(0)
        try await fixture.beginRound(1, pids: [0x0C, 0x0D])
        try await fixture.record(1, 0, .responded([250]), valueOutcome: .invalidValue)
        try await fixture.record(1, 1, pid: 0x0D, .unsupported)
        try await fixture.finishRound(1)

        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        let batches = try fixture.acquisition.batches(for: fixture.sessionID)
        XCTAssertEqual(batches[0].requests.map(\.requestOrdinal), [0])
        XCTAssertEqual(batches[0].requests.map(\.manifestPIDOrdinal), [1])
        XCTAssertEqual(batches[0].requests.map(\.valueOutcome), [.decodeFailure])
        XCTAssertEqual(batches[0].requests.map(\.rawSequence), [0])
        XCTAssertEqual(batches[1].requests.map(\.valueOutcome), [.invalidValue, .notEvaluated])
        XCTAssertEqual(batches[1].requests.map(\.transportOutcome), [.responded, .unsupported])
        XCTAssertEqual(batches[1].requests.map(\.reasonCode), [nil, "explicit_unsupported"])
        XCTAssertEqual(batches[1].completionState, .completed)
        XCTAssertEqual(try fixture.storedRaws().map(\.payload), [[1], [250]])
    }

    /// Raw・batch・requestの全行数を返します。
    ///
    /// 責務: セッションを問わず3表の行数を数えます。
    /// - Parameter queue: 数えるDB Queue。
    /// - Returns: (Raw数, batch数, request数)。
    /// - Throws: SQLite読込失敗。
    private func rowCounts(_ queue: DatabaseQueue) throws -> [Int] {
        try queue.read { database in
            [
                try ConnectionSessionRawLogRecord.fetchCount(database),
                try ConnectionSessionAcquisitionBatchRecord.fetchCount(database),
                try ConnectionSessionAcquisitionPIDRequestRecord.fetchCount(database)
            ]
        }
    }
}
