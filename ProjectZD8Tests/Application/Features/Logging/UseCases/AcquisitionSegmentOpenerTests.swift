import Foundation
import XCTest
@testable import ProjectZD8

/// 取得開始時の連続取得区間の開始と、未終了区間の後始末、欠損番号の続きを検証します。
final class AcquisitionSegmentOpenerTests: XCTestCase {
    /// 区間が無ければ番号0・開始理由 initial で開き、欠損が無ければ欠損番号は0から始めます。
    ///
    /// 責務: 最初の区間の内容と欠損番号の初期値を確認します。
    func testOpensInitialSegmentWhenNoneExists() throws {
        let segments = AcquisitionSegmentRepositorySpy()
        let opener = AcquisitionSegmentOpener(segmentRepository: segments, gapRepository: AcquisitionGapRepositorySpy())

        let opened = try opener.open(for: sessionID, firstSequence: 0, startedAt: date(100), monotonicAnchorNanoseconds: 9)

        XCTAssertEqual(opened, AcquisitionSegmentOpener.Opened(segmentOrdinal: 0, nextGapOrdinal: 0))
        XCTAssertEqual(try segments.segments(for: sessionID), [ConnectionSessionSegment(
            segmentOrdinal: 0, startReason: .initial, acquisitionMode: .pidPolling,
            startedAt: date(100), monotonicAnchorNanoseconds: 9, firstSequence: 0
        )])
    }

    /// 未終了の区間は接続喪失で閉じ、最終連番を新しい区間の直前、開始日時以上の終了日時にします。
    ///
    /// 責務: 未終了区間の終了内容と、再接続の区間の番号・開始理由を確認します。
    func testClosesDanglingSegmentBeforeOpeningReconnected() throws {
        let segments = AcquisitionSegmentRepositorySpy(segments: [segment(0, firstSequence: 2, startedAt: 200)])
        let opener = AcquisitionSegmentOpener(segmentRepository: segments, gapRepository: AcquisitionGapRepositorySpy())

        let opened = try opener.open(for: sessionID, firstSequence: 6, startedAt: date(150), monotonicAnchorNanoseconds: 1)

        let stored = try segments.segments(for: sessionID)
        XCTAssertEqual(opened.segmentOrdinal, 1)
        XCTAssertEqual(stored[0].endReason, .linkLost)
        XCTAssertEqual(stored[0].lastSequence, 5)
        XCTAssertEqual(stored[0].endedAt, date(200))
        XCTAssertEqual(stored[1].startReason, .reconnected)
        XCTAssertEqual(stored[1].firstSequence, 6)
    }

    /// 未終了の区間に1行も無ければ、最終連番は無しで閉じます。
    ///
    /// 責務: 新しい区間の直前が未終了区間の最初の連番より前になる境界を確認します。
    func testDanglingSegmentWithoutRowsClosesWithoutLastSequence() throws {
        let segments = AcquisitionSegmentRepositorySpy(segments: [segment(0, firstSequence: 4, startedAt: 10)])
        let opener = AcquisitionSegmentOpener(segmentRepository: segments, gapRepository: AcquisitionGapRepositorySpy())

        _ = try opener.open(for: sessionID, firstSequence: 4, startedAt: date(20), monotonicAnchorNanoseconds: 1)

        let stored = try segments.segments(for: sessionID)
        XCTAssertEqual(stored[0].endReason, .linkLost)
        XCTAssertNil(stored[0].lastSequence)
        XCTAssertEqual(stored[0].endedAt, date(20))
    }

    /// 終了済みの区間はそのままにして次の番号で開き、欠損番号は既存の最大の次から続けます。
    ///
    /// 責務: 終了済み区間を閉じ直さないことと、欠損番号の続きを確認します。
    func testEndedSegmentIsKeptAndGapOrdinalContinues() throws {
        let ended = ConnectionSessionSegment(
            segmentOrdinal: 3, startReason: .initial, acquisitionMode: .pidPolling, startedAt: date(1),
            monotonicAnchorNanoseconds: 1, firstSequence: 0, endedAt: date(2), endReason: .sessionEnded, lastSequence: 9
        )
        let segments = AcquisitionSegmentRepositorySpy(segments: [ended])
        let gaps = AcquisitionGapRepositorySpy(gaps: [
            ConnectionSessionGap(gapOrdinal: 6, precedingSegmentOrdinal: 3, startedAt: date(2), cause: .linkLost)
        ])
        let opener = AcquisitionSegmentOpener(segmentRepository: segments, gapRepository: gaps)

        let opened = try opener.open(for: sessionID, firstSequence: 10, startedAt: date(30), monotonicAnchorNanoseconds: 1)

        XCTAssertEqual(opened, AcquisitionSegmentOpener.Opened(segmentOrdinal: 4, nextGapOrdinal: 7))
        XCTAssertEqual(try segments.segments(for: sessionID).first, ended)
    }

    /// 区間を閉じられなければ失敗を送出し、新しい区間を開きません。
    ///
    /// 責務: 区間Repositoryの失敗を握りつぶさないことを確認します。
    func testFinishFailurePropagates() throws {
        let segments = AcquisitionSegmentRepositorySpy(segments: [segment(0, firstSequence: 0, startedAt: 1)], failsFinish: true)
        let opener = AcquisitionSegmentOpener(segmentRepository: segments, gapRepository: AcquisitionGapRepositorySpy())

        XCTAssertThrowsError(try opener.open(for: sessionID, firstSequence: 3, startedAt: date(5), monotonicAnchorNanoseconds: 1))
        XCTAssertEqual(try segments.segments(for: sessionID).count, 1)
    }

    /// テスト用のセッションIDです。
    private let sessionID = ConnectionSessionID()

    /// 指定秒の日時を返します。
    ///
    /// 責務: 1970年起点の秒を日時へ変換します。
    /// - Parameter seconds: 秒。
    /// - Returns: 日時。
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    /// 未終了の区間を生成します。
    ///
    /// 責務: 番号・最初の連番・開始日時だけを差し替えた未終了区間を返します。
    /// - Parameters:
    ///   - ordinal: 区間番号。
    ///   - firstSequence: 最初の連番。
    ///   - startedAt: 開始日時の秒。
    /// - Returns: 未終了の区間。
    private func segment(_ ordinal: Int, firstSequence: Int64, startedAt: TimeInterval) -> ConnectionSessionSegment {
        ConnectionSessionSegment(
            segmentOrdinal: ordinal, startReason: .initial, acquisitionMode: .pidPolling,
            startedAt: date(startedAt), monotonicAnchorNanoseconds: 1, firstSequence: firstSequence
        )
    }
}
