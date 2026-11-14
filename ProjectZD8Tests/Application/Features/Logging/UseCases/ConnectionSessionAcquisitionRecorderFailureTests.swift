import Foundation
import XCTest
@testable import ProjectZD8

/// 取得記録のcommit失敗・欠損記録失敗・世代違い・不正入力・開始失敗の扱いを検証します。
@MainActor
final class ConnectionSessionAcquisitionRecorderFailureTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture

    /// commitに失敗したチャンクは再送されず、最初と最後の実時刻を持つ bufferOverflow の欠損が1件記録され、次のチャンクは保存されます。
    ///
    /// 責務: 失敗チャンクの欠損の内容、失敗の非伝播、次チャンクの内容と連番、失敗チャンクの不再送を確認します。
    func testCommitFailureRecordsBufferOverflowGapAndNextChunkIsSaved() async throws {
        let gaps = AcquisitionGapRepositorySpy()
        let fixture = try Fixture(failingCommits: [0], gapRepository: gaps)
        try await fixture.start()
        let (first, observed, last) = (Date(timeIntervalSince1970: 1_010), Date(timeIntervalSince1970: 1_011), Date(timeIntervalSince1970: 1_012))
        fixture.dates.set(first)
        try await fixture.beginRound(0)
        fixture.dates.set(observed)
        try await fixture.record(0, 0, .responded([1]))
        fixture.dates.set(last)
        try await fixture.finishRound(0)

        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        XCTAssertEqual(try gaps.gaps(for: fixture.sessionID), [ConnectionSessionGap(
            gapOrdinal: 0, precedingSegmentOrdinal: 0, followingSegmentOrdinal: 0,
            startedAt: first, endedAt: last, cause: .bufferOverflow
        )])
        try await fixture.respondedRound(1, payload: 2)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        XCTAssertEqual(fixture.chunks.attempts.count, 2)
        XCTAssertEqual(fixture.chunks.committed.count, 1)
        XCTAssertEqual(fixture.chunks.committed.first?.batches.map(\.identity.ordinal), [1])
        XCTAssertEqual(fixture.chunks.committed.first?.rawEntries.map(\.payload), [[2]])
        XCTAssertEqual(try gaps.gaps(for: fixture.sessionID).count, 1)
    }

    /// 欠損番号は既存の最大番号の次から割り当てます。
    ///
    /// 責務: 保存済みの欠損と番号が重ならないことを確認します。
    func testGapOrdinalContinuesAfterExistingGaps() async throws {
        let existing = ConnectionSessionGap(gapOrdinal: 4, precedingSegmentOrdinal: 0, startedAt: Date(timeIntervalSince1970: 5), cause: .linkLost)
        let gaps = AcquisitionGapRepositorySpy(gaps: [existing])
        let fixture = try Fixture(failingCommits: [0], gapRepository: gaps)
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 1)

        try await fixture.recorder.flush(.segmentEnded, generation: 1)

        XCTAssertEqual(try gaps.gaps(for: fixture.sessionID).map(\.gapOrdinal), [4, 5])
    }

    /// 欠損の記録にも失敗すると保存失敗が呼び出し元へ返り、以後の記録と終了も保存失敗になります。
    ///
    /// 責務: 保存も欠損記録もできない状態を成功扱いせず、取得を続けさせないことを確認します。
    func testGapSaveFailureReturnsStorageFailedAndStopsRecording() async throws {
        let fixture = try Fixture(failingCommits: [0], gapRepository: AcquisitionGapRepositorySpy(failsSave: true))
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 1)

        await assertStorageFailed { try await fixture.recorder.flush(.backgroundTransition, generation: 1) }
        await assertStorageFailed { try await fixture.beginRound(1) }
        await assertStorageFailed { try await fixture.recorder.finish(generation: 1, reason: .userDisconnected) }
    }

    /// 古い世代や開始前・終了後の記録は拒否され、flushと終了は何もしません。
    ///
    /// 責務: 世代違いの周回開始・要求結果・周回終了が `inactiveGeneration` になり、保存も区間終了も起きないことを確認します。
    func testRecordsFromInactiveGenerationAreRejected() async throws {
        let segments = AcquisitionSegmentRepositorySpy()
        let fixture = try Fixture(segmentRepository: segments)
        await assertError(.inactiveGeneration) { try await fixture.beginRound(0) }
        try await fixture.start(generation: 2)
        try await fixture.respondedRound(0, payload: 1, generation: 2)

        await assertError(.inactiveGeneration) { try await fixture.beginRound(1, generation: 1) }
        await assertError(.inactiveGeneration) { try await fixture.record(0, 0, .responded([1]), generation: 1) }
        await assertError(.inactiveGeneration) { try await fixture.finishRound(0, generation: 1) }
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        try await fixture.recorder.finish(generation: 1, reason: .userDisconnected)

        XCTAssertEqual(fixture.chunks.attempts.count, 0)
        XCTAssertNil(try segments.segments(for: fixture.sessionID).first?.endedAt)
        try await fixture.recorder.finish(generation: 2, reason: .userDisconnected)
        await assertError(.inactiveGeneration) { try await fixture.beginRound(1, generation: 2) }
    }

    /// manifestに無い要求・重複・空の周回、開いた周回の二重開始は入力不正です。
    ///
    /// 責務: 周回開始の不正な要求列を記録せずに拒否することを確認します。
    func testInvalidRoundsAreRejected() async throws {
        let fixture = try Fixture()
        try await fixture.start()

        await assertError(.invalidInput) { try await fixture.beginRound(0, pids: [0x05]) }
        await assertError(.invalidInput) { try await fixture.beginRound(0, pids: [0x0C, 0x0C]) }
        await assertError(.invalidInput) { try await fixture.beginRound(0, pids: []) }
        try await fixture.beginRound(0)
        await assertError(.invalidInput) { try await fixture.beginRound(1) }
    }

    /// 順序違い・要求違い・周回違いの要求結果と、未終了要求の残る周回終了は入力不正です。
    ///
    /// 責務: 要求結果と周回終了の不正な組合せを拒否することを確認します。
    func testInvalidResultsAndFinishesAreRejected() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        try await fixture.beginRound(0, pids: [0x0C, 0x0D])

        await assertError(.invalidInput) { try await fixture.record(0, 1, pid: 0x0D, .responded([1])) }
        await assertError(.invalidInput) { try await fixture.record(0, 0, pid: 0x0D, .responded([1])) }
        await assertError(.invalidInput) { try await fixture.record(1, 0, .responded([1])) }
        await assertError(.invalidInput) { try await fixture.record(0, 0, pid: 0x05, .responded([1])) }
        await assertError(.invalidInput) { try await fixture.finishRound(0) }
        try await fixture.record(0, 0, .responded([1]))
        await assertError(.invalidInput) { try await fixture.finishRound(1) }
    }

    /// 現在のセッションが無ければ開始は失敗し、manifestも区間も作らず、性能eventは失敗で閉じます。
    ///
    /// 責務: 親セッション不在を最初の要求より前の失敗へ変換することを確認します。
    func testStartWithoutActiveSessionFailsBeforeAnyRecord() async throws {
        let segments = AcquisitionSegmentRepositorySpy()
        let fixture = try Fixture(segmentRepository: segments, exposesSession: false)

        do {
            try await fixture.start()
            XCTFail("セッション不在の開始が成功しました")
        } catch {
            XCTAssertEqual(error as? ConnectionSessionRepositoryError, .invalidState)
        }

        XCTAssertThrowsError(try fixture.acquisition.manifest(for: fixture.sessionID)) {
            XCTAssertEqual($0 as? ConnectionSessionAcquisitionRepositoryError, .notFound)
        }
        XCTAssertEqual(try segments.segments(for: fixture.sessionID), [])
        XCTAssertEqual(fixture.performance.events, [.begin(.acquisitionStart, generation: 1), .end(.acquisitionStart, .failed)])
        await assertError(.inactiveGeneration) { try await fixture.beginRound(0) }
    }

    /// 開始と終了が性能eventの区間として成功で閉じます。
    ///
    /// 責務: 取得開始と世代終了の区間が世代付きで開始・終了されることを確認します。
    func testStartAndFinishEmitPerformanceIntervals() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        try await fixture.recorder.finish(generation: 1, reason: .userDisconnected)

        XCTAssertEqual(fixture.performance.events, [
            .begin(.acquisitionStart, generation: 1), .end(.acquisitionStart, .succeeded),
            .begin(.generationCancellation, generation: 1), .end(.generationCancellation, .succeeded)
        ])
    }

    /// 処理が保存失敗を送出することを検証します。
    ///
    /// 責務: 送出されたエラーが `.storageFailed` であることを確認し、成功した場合は失敗させます。
    /// - Parameters:
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - operation: 検証する処理。
    private func assertStorageFailed(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        await assertError(.storageFailed, file: file, line: line, operation)
    }

    /// 処理が指定の記録エラーを送出することを検証します。
    ///
    /// 責務: 送出されたエラーのcaseを確認し、成功した場合は失敗させます。
    /// - Parameters:
    ///   - expected: 期待する記録エラー。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    ///   - operation: 検証する処理。
    private func assertError(
        _ expected: LiveTelemetryAcquisitionRecordingError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("\(expected) を期待しましたが成功しました", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LiveTelemetryAcquisitionRecordingError, expected, file: file, line: line)
        }
    }
}
