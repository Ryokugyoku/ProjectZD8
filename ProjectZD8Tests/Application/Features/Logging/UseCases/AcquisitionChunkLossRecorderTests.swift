import Foundation
import XCTest
@testable import ProjectZD8

/// 破棄したチャンクを bufferOverflow の欠損として記録することを検証します。
final class AcquisitionChunkLossRecorderTests: XCTestCase {
    /// 欠損の前後の区間はチャンクの最初・最後のRawの区間、時刻はチャンクの最初・最後の実時刻です。
    ///
    /// 責務: Rawを含むチャンクから作る欠損の全項目を確認します。
    func testLossUsesChunkSegmentsAndTimeSpan() throws {
        let gaps = AcquisitionGapRepositorySpy()
        let sessionID = ConnectionSessionID()

        try AcquisitionChunkLossRecorder(gapRepository: gaps).recordLoss(
            of: pending(firstSegment: 1, lastSegment: 2), gapOrdinal: 8, currentSegmentOrdinal: 5, for: sessionID
        )

        XCTAssertEqual(try gaps.gaps(for: sessionID), [ConnectionSessionGap(
            gapOrdinal: 8, precedingSegmentOrdinal: 1, followingSegmentOrdinal: 2,
            startedAt: Date(timeIntervalSince1970: 10), endedAt: Date(timeIntervalSince1970: 20), cause: .bufferOverflow
        )])
    }

    /// Rawの無いチャンクでは、前後の区間を現在の区間にします。
    ///
    /// 責務: 区間番号が無いチャンクの欠損の前後区間を確認します。
    func testLossWithoutRawsUsesCurrentSegment() throws {
        let gaps = AcquisitionGapRepositorySpy()
        let sessionID = ConnectionSessionID()

        try AcquisitionChunkLossRecorder(gapRepository: gaps).recordLoss(
            of: pending(firstSegment: nil, lastSegment: nil), gapOrdinal: 0, currentSegmentOrdinal: 5, for: sessionID
        )

        let gap = try XCTUnwrap(gaps.gaps(for: sessionID).first)
        XCTAssertEqual(gap.precedingSegmentOrdinal, 5)
        XCTAssertEqual(gap.followingSegmentOrdinal, 5)
    }

    /// 欠損を保存できなければ失敗を送出します。
    ///
    /// 責務: 欠損Repositoryの失敗を握りつぶさないことを確認します。
    func testSaveFailurePropagates() {
        let recorder = AcquisitionChunkLossRecorder(gapRepository: AcquisitionGapRepositorySpy(failsSave: true))

        XCTAssertThrowsError(try recorder.recordLoss(
            of: pending(firstSegment: 0, lastSegment: 0), gapOrdinal: 0, currentSegmentOrdinal: 0, for: ConnectionSessionID()
        ))
    }

    /// 破棄したチャンクを生成します。
    ///
    /// 責務: 時刻範囲と区間番号だけを指定した保存待ちチャンクを返します。
    /// - Parameters:
    ///   - firstSegment: 最初のRawの区間番号。
    ///   - lastSegment: 最後のRawの区間番号。
    /// - Returns: 保存待ちチャンク。
    private func pending(firstSegment: Int?, lastSegment: Int?) -> AcquisitionPendingChunk {
        AcquisitionPendingChunk(
            chunk: ConnectionSessionAcquisitionChunk(sessionID: ConnectionSessionID(), rawEntries: [], batches: []),
            batchCount: 1, nextSequenceAfterCommit: 0,
            firstObservedAt: Date(timeIntervalSince1970: 10), lastObservedAt: Date(timeIntervalSince1970: 20),
            firstSegmentOrdinal: firstSegment, lastSegmentOrdinal: lastSegment
        )
    }
}
