import Foundation
import XCTest
@testable import ProjectZD8

/// 区間の終了と、欠損を挟んだ次の区間の開始を検証します。
final class AcquisitionSegmentSwitcherTests: XCTestCase {
    /// テスト用のセッションIDです。
    private let sessionID = ConnectionSessionID()

    /// 区間の終了日時は区間の開始日時を下限にし、最終連番は区間の最初の連番以上の時だけ残します。
    ///
    /// 責務: 終了日時の下限と最終連番の境界を確認します。
    func testCloseClampsEndAndLastSequence() throws {
        for (lastCommitted, expected) in [(Int64?.some(40), Int64?.some(40)), (39, nil), (nil, nil)] {
            let segments = AcquisitionSegmentRepositorySpy(segments: [openSegment()])
            let switcher = AcquisitionSegmentSwitcher(segmentRepository: segments, gapRepository: AcquisitionGapRepositorySpy())

            try switcher.close(session(), endedAt: date(1), reason: .responseStall, lastCommittedSequence: lastCommitted)

            let stored = try XCTUnwrap(segments.segments(for: sessionID).first)
            XCTAssertEqual(stored.endedAt, date(7), "\(String(describing: lastCommitted))")
            XCTAssertEqual(stored.endReason, .responseStall)
            XCTAssertEqual(stored.lastSequence, expected, "\(String(describing: lastCommitted))")
        }
    }

    /// 欠損付きで開くと、次の番号の区間を開き、欠損を前後の区間と再開日時付きで閉じます。欠損の開始は再開日時を上限にします。
    ///
    /// 責務: 新しい区間の内容、欠損の内容、返す区間番号、開始が再開より後の欠損の扱いを確認します。
    func testOpenWithGapRecordsGapAndNextSegment() throws {
        let segments = AcquisitionSegmentRepositorySpy(segments: [openSegment()])
        let gaps = AcquisitionGapRepositorySpy()
        let switcher = AcquisitionSegmentSwitcher(segmentRepository: segments, gapRepository: gaps)
        let gap = AcquisitionSegmentSwitcher.Gap(ordinal: 4, startedAt: date(30), cause: .linkLost)

        let ordinal = try switcher.open(
            after: session(), startReason: .reconnected, startedAt: date(20), anchorNanoseconds: 77, firstSequence: 41, gap: gap
        )

        XCTAssertEqual(ordinal, 3)
        XCTAssertEqual(try segments.segments(for: sessionID).last, ConnectionSessionSegment(
            segmentOrdinal: 3, startReason: .reconnected, acquisitionMode: .pidPolling,
            startedAt: date(20), monotonicAnchorNanoseconds: 77, firstSequence: 41
        ))
        XCTAssertEqual(try gaps.gaps(for: sessionID), [ConnectionSessionGap(
            gapOrdinal: 4, precedingSegmentOrdinal: 2, followingSegmentOrdinal: 3,
            startedAt: date(20), endedAt: date(20), cause: .linkLost
        )])
    }

    /// 欠損なしで開くと、区間だけを開きます。
    ///
    /// 責務: モード切替のような欠損なしの開始で欠損が作られないことを確認します。
    func testOpenWithoutGapRecordsOnlySegment() throws {
        let segments = AcquisitionSegmentRepositorySpy(segments: [openSegment()])
        let gaps = AcquisitionGapRepositorySpy()
        let switcher = AcquisitionSegmentSwitcher(segmentRepository: segments, gapRepository: gaps)

        _ = try switcher.open(after: session(), startReason: .modeSwitched, startedAt: date(20), anchorNanoseconds: 1, firstSequence: 41, gap: nil)

        XCTAssertEqual(try segments.segments(for: sessionID).last?.startReason, .modeSwitched)
        XCTAssertEqual(try gaps.gaps(for: sessionID), [])
    }

    /// 区間・欠損の保存の失敗はそのまま送出されます。
    ///
    /// 責務: 区間の終了・開始、欠損の保存・終了の失敗を握りつぶさないことを確認します。
    func testStorageFailuresPropagate() {
        let gap = AcquisitionSegmentSwitcher.Gap(ordinal: 0, startedAt: date(10), cause: .responseStall)
        let failures: [(AcquisitionSegmentRepositorySpy, AcquisitionGapRepositorySpy)] = [
            (AcquisitionSegmentRepositorySpy(segments: [openSegment()], failingBeginsAfter: 0), AcquisitionGapRepositorySpy()),
            (AcquisitionSegmentRepositorySpy(segments: [openSegment()]), AcquisitionGapRepositorySpy(failsSave: true)),
            (AcquisitionSegmentRepositorySpy(segments: [openSegment()]), AcquisitionGapRepositorySpy(failsFinish: true))
        ]
        for (segments, gaps) in failures {
            let switcher = AcquisitionSegmentSwitcher(segmentRepository: segments, gapRepository: gaps)
            XCTAssertThrowsError(try switcher.open(
                after: session(), startReason: .reconnected, startedAt: date(20), anchorNanoseconds: 1, firstSequence: 41, gap: gap
            ))
        }
        let closing = AcquisitionSegmentSwitcher(
            segmentRepository: AcquisitionSegmentRepositorySpy(segments: [openSegment()], failsFinish: true),
            gapRepository: AcquisitionGapRepositorySpy()
        )
        XCTAssertThrowsError(try closing.close(session(), endedAt: date(9), reason: .linkLost, lastCommittedSequence: nil))
    }

    /// 番号2・最初の連番40・開始日時7秒の記録状態を返します。
    ///
    /// 責務: 区間切替の入力にする記録状態を生成します。
    /// - Returns: 記録状態。
    private func session() -> AcquisitionRecordingSession {
        AcquisitionRecordingSession(
            sessionID: sessionID, generation: 1, orderedRequests: [OBDPIDRequest(service: 0x01, pid: 0x0C)],
            segmentOrdinal: 2, segmentFirstSequence: 40, segmentStartedAt: date(7), nextGapOrdinal: 0, anchorNanoseconds: 0
        )
    }

    /// 記録状態と同じ番号の未終了区間を返します。
    ///
    /// 責務: 区間Repositoryの既存区間を生成します。
    /// - Returns: 未終了の区間。
    private func openSegment() -> ConnectionSessionSegment {
        ConnectionSessionSegment(
            segmentOrdinal: 2, startReason: .reconnected, acquisitionMode: .pidPolling,
            startedAt: date(7), monotonicAnchorNanoseconds: 0, firstSequence: 40
        )
    }

    /// 指定秒の日時を返します。
    ///
    /// 責務: 1970年起点の秒を日時へ変換します。
    /// - Parameter seconds: 秒。
    /// - Returns: 日時。
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
