import Foundation
import XCTest
@testable import ProjectZD8

/// メモリ上のGRDBへ、区間の切替・欠損・連番・単調時計が制約を満たして保存されることを検証します。
@MainActor
final class ConnectionSessionAcquisitionRecorderSegmentSwitchGRDBTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture

    /// 再接続で復帰すると、DBに欠損1件と新しい区間1件が保存され、連番は欠番も重複もなく続き、単調時計は区間内で減りません。
    ///
    /// 責務: 区間・欠損・Rawの保存内容と、新区間の最初の連番が次に保存されたRawの連番と一致することを確認します。
    func testReconnectPersistsGapSegmentAndContiguousRaws() async throws {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        let lastReceive = Date(timeIntervalSince1970: 1_020)
        fixture.clock.set(nanoseconds: 9_000)
        fixture.dates.set(lastReceive)
        try await fixture.respondedRound(0, payload: 1)
        try await fixture.respondedRound(1, payload: 2)
        try await fixture.endSegment(.linkLost, lastReceivedAt: lastReceive)
        fixture.clock.set(nanoseconds: 6_000)
        fixture.dates.set(Date(timeIntervalSince1970: 1_080))

        try await fixture.beginSegment(cause: .linkLost, gapStartedAt: lastReceive)
        fixture.clock.set(nanoseconds: 6_500)
        try await fixture.respondedRound(2, payload: 3)
        fixture.clock.set(nanoseconds: 6_400)
        try await fixture.respondedRound(3, payload: 4)
        try await fixture.recorder.finish(generation: 1, reason: .userDisconnected)

        let segments = try fixture.segments.segments(for: fixture.sessionID)
        XCTAssertEqual(segments.map(\.startReason), [.initial, .reconnected])
        XCTAssertEqual(segments.map(\.endReason), [.linkLost, .sessionEnded])
        XCTAssertEqual(segments.map(\.lastSequence), [1, 3])
        let gaps = try fixture.gaps.gaps(for: fixture.sessionID)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.cause, .linkLost)
        XCTAssertEqual(gaps.first?.startedAt, lastReceive)
        XCTAssertEqual(gaps.first?.endedAt, Date(timeIntervalSince1970: 1_080))
        XCTAssertEqual(gaps.first?.precedingSegmentOrdinal, 0)
        XCTAssertEqual(gaps.first?.followingSegmentOrdinal, 1)
        let raws = try fixture.storedRaws()
        XCTAssertEqual(raws.map(\.sequence), [0, 1, 2, 3])
        XCTAssertEqual(raws.map(\.segmentOrdinal), [0, 0, 1, 1])
        XCTAssertEqual(segments.last?.firstSequence, raws.first { $0.segmentOrdinal == 1 }?.sequence)
        assertMonotonicNonDecreasingPerSegment(raws)
    }

    /// モード切替はDBの制約を満たして保存され、欠損は保存されません。
    ///
    /// 責務: modeSwitched の終了・開始の区間と、欠損0件をGRDBで確認します。
    func testModeSwitchPersistsWithoutGap() async throws {
        let fixture = try Fixture(storage: .grdb)
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 1)

        try await fixture.recorder.switchMode(generation: 1)
        try await fixture.respondedRound(1, payload: 2)
        try await fixture.recorder.flush(.segmentEnded, generation: 1)

        let segments = try fixture.segments.segments(for: fixture.sessionID)
        XCTAssertEqual(segments.map(\.startReason), [.initial, .modeSwitched])
        XCTAssertEqual(segments.first?.endReason, .modeSwitched)
        XCTAssertEqual(try fixture.gaps.gaps(for: fixture.sessionID), [])
        XCTAssertEqual(try fixture.storedRaws().map(\.segmentOrdinal), [0, 1])
    }

    /// 区間ごとに単調時計の値が減らないことを検証します。
    ///
    /// 責務: 同じ区間番号のRawの単調時計を連番順に比べます。
    /// - Parameters:
    ///   - raws: 連番順のRaw。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    private func assertMonotonicNonDecreasingPerSegment(
        _ raws: [ConnectionSessionRawLogEntry],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let bySegment = Dictionary(grouping: raws) { $0.segmentOrdinal ?? -1 }
        for (segment, entries) in bySegment {
            let values = entries.compactMap(\.monotonicNanoseconds)
            XCTAssertEqual(values.count, entries.count, "区間 \(segment)", file: file, line: line)
            XCTAssertEqual(values, values.sorted(), "区間 \(segment)", file: file, line: line)
        }
    }
}
