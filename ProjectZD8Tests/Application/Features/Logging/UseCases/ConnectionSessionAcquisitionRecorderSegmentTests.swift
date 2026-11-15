import Foundation
import XCTest
@testable import ProjectZD8

/// 取得記録の開始・終了で連続取得区間を開き、閉じ、未完了の周回を打ち切ることを検証します。
@MainActor
final class ConnectionSessionAcquisitionRecorderSegmentTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture

    /// セッション開始で、開始理由 initial の1つ目の区間が1件記録され、最初のRawは次の記録順序から採番されます。
    ///
    /// 責務: 区間の番号・開始理由・取得方式・開始日時・単調時計の起点・最初の連番と、最初のチャンクの連番を確認します。
    func testStartOpensInitialSegmentAtNextRawSequence() async throws {
        let segments = AcquisitionSegmentRepositorySpy()
        let fixture = try Fixture(segmentRepository: segments, nextRawSequence: 7)

        try await fixture.start()
        try await fixture.respondedRound(0, payload: 1)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        XCTAssertEqual(try segments.segments(for: fixture.sessionID), [ConnectionSessionSegment(
            segmentOrdinal: 0, startReason: .initial, acquisitionMode: .pidPolling,
            startedAt: Fixture.startDate, monotonicAnchorNanoseconds: 5_000, firstSequence: 7
        )])
        XCTAssertEqual(fixture.chunks.attempts.first?.rawEntries.map(\.sequence), [7])
    }

    /// 終了していない区間が残っていれば、それを接続喪失で閉じてから再接続の区間を開きます。
    ///
    /// 責務: 既存区間の最終連番と、新しい区間の番号・開始理由・最初の連番を確認します。
    func testStartClosesDanglingSegmentAndOpensReconnectedSegment() async throws {
        let dangling = ConnectionSessionSegment(
            segmentOrdinal: 0, startReason: .initial, acquisitionMode: .pidPolling,
            startedAt: Date(timeIntervalSince1970: 500), monotonicAnchorNanoseconds: 1, firstSequence: 0
        )
        let segments = AcquisitionSegmentRepositorySpy(segments: [dangling])
        let fixture = try Fixture(segmentRepository: segments, nextRawSequence: 3)

        try await fixture.start()

        let stored = try segments.segments(for: fixture.sessionID)
        XCTAssertEqual(stored.map(\.segmentOrdinal), [0, 1])
        XCTAssertEqual(stored[0].endReason, .linkLost)
        XCTAssertEqual(stored[0].lastSequence, 2)
        XCTAssertEqual(stored[1].startReason, .reconnected)
        XCTAssertEqual(stored[1].firstSequence, 3)
        XCTAssertNil(stored[1].endedAt)
    }

    /// 終了で区間を閉じ、終了理由を接続断なら接続喪失、それ以外ならセッション終了にします。
    ///
    /// 責務: 終了理由の変換と、最終連番がcommit済みの最後の番号(無ければnil)になることを確認します。
    func testFinishClosesSegmentWithReasonAndLastCommittedSequence() async throws {
        let cases: [(ConnectionSessionEndReason, Bool, ConnectionSessionSegmentEndReason, Int64?)] = [
            (.userDisconnected, true, .sessionEnded, 1),
            (.vehicleNoResponse, false, .sessionEnded, nil),
            (.connectionLost, true, .linkLost, 1)
        ]
        for (reason, recordsRaws, expectedReason, expectedLast) in cases {
            let segments = AcquisitionSegmentRepositorySpy()
            let fixture = try Fixture(segmentRepository: segments)
            try await fixture.start()
            if recordsRaws {
                try await fixture.respondedRound(0, payload: 1)
                try await fixture.respondedRound(1, payload: 2)
            }
            fixture.dates.set(Date(timeIntervalSince1970: 2_000))

            try await fixture.recorder.finish(generation: 1, reason: reason)

            let segment = try XCTUnwrap(segments.segments(for: fixture.sessionID).first)
            XCTAssertEqual(segment.endReason, expectedReason, "\(reason)")
            XCTAssertEqual(segment.lastSequence, expectedLast, "\(reason)")
            XCTAssertEqual(segment.endedAt, Date(timeIntervalSince1970: 2_000), "\(reason)")
        }
    }

    /// 終了時に未完了の周回は取消として打ち切られ、送っていない要求は選択のみのまま保存されます。
    ///
    /// 責務: 途中までの周回が失敗・取消のbatchになり、記録済みのRawを残してcommitされることを確認します。
    func testFinishAbandonsOpenRoundAsCancelled() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        try await fixture.beginRound(0, pids: [0x0C, 0x0D])
        try await fixture.record(0, 0, .responded([9]))

        try await fixture.recorder.finish(generation: 1, reason: .userDisconnected)

        let batch = try XCTUnwrap(fixture.chunks.attempts.first?.batches.first)
        XCTAssertEqual(batch.completionState, .failed)
        XCTAssertEqual(batch.failure, .cancelled)
        XCTAssertEqual(batch.requests.map(\.dispatchState), [.terminal, .selectedOnly])
        XCTAssertEqual(batch.requests.map(\.transportOutcome), [.responded, nil])
        XCTAssertEqual(fixture.chunks.attempts.first?.rawEntries.map(\.payload), [[9]])
    }

    /// 終了時に全要求の結果が揃っていて周回終了だけが未記録なら、通常どおり完了で確定します。
    ///
    /// 責務: 全要求が終わった周回を取消扱いしないことを確認します。
    func testFinishSealsFullyAnsweredRoundAsCompleted() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        try await fixture.beginRound(0)
        try await fixture.record(0, 0, .responded([9]))

        try await fixture.recorder.finish(generation: 1, reason: .userDisconnected)

        let batch = try XCTUnwrap(fixture.chunks.attempts.first?.batches.first)
        XCTAssertEqual(batch.completionState, .completed)
        XCTAssertNil(batch.failure)
    }

    /// 区間を閉じられなければ終了は保存失敗になります。
    ///
    /// 責務: 区間終了の失敗を成功扱いしないことを確認します。
    func testFinishFailsWhenSegmentCannotBeClosed() async throws {
        let fixture = try Fixture(segmentRepository: AcquisitionSegmentRepositorySpy(failsFinish: true))
        try await fixture.start()

        do {
            try await fixture.recorder.finish(generation: 1, reason: .userDisconnected)
            XCTFail("区間を閉じられないのに終了が成功しました")
        } catch {
            XCTAssertEqual(error as? LiveTelemetryAcquisitionRecordingError, .storageFailed)
        }
    }
}
