import Foundation
import XCTest
@testable import ProjectZD8

/// 取得記録が途絶で区間を閉じ、復帰で欠損と次の区間を記録し、モード切替で区間を切り替えることをフェイクの保存先で検証します。
@MainActor
final class ConnectionSessionAcquisitionRecorderSegmentSwitchTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture
    /// 最後の受信の実時刻です。
    private let lastReceive = Date(timeIntervalSince1970: 1_010)
    /// 再開の実時刻です。
    private let resumedAt = Date(timeIntervalSince1970: 1_050)

    /// 再接続で復帰すると、前の区間がリンク断で閉じ、欠損と再接続の区間がちょうど1件ずつ記録されます。
    ///
    /// 責務: 区間の終了理由・終了日時・最終連番と、欠損の原因・開始・終了・前後区間、新区間の開始理由・開始日時・最初の連番を確認します。
    func testLinkLossResumptionRecordsOneGapAndOneSegment() async throws {
        try await assertResumption(reason: .linkLost, cause: .linkLost)
    }

    /// プロンプト再同期やATZ再初期化で復帰した応答途絶も、欠損(responseStall)と新しい区間をちょうど1件ずつ記録します。
    ///
    /// 責務: 応答途絶の終了理由と欠損原因で同じ記録になることを確認します。
    func testStallResumptionRecordsOneGapAndOneSegment() async throws {
        try await assertResumption(reason: .responseStall, cause: .responseStall)
    }

    /// 区間を閉じる前に保存待ちの記録をcommitし、閉じる前に受けたRawは前の区間番号で保存されます。
    ///
    /// 責務: 未完了の周回のRawが区間終了時に打ち切りでcommitされ、再開後のRawが新しい区間番号になることを確認します。
    func testPendingRecordsAreFlushedBeforeSwitch() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        try await fixture.beginRound(0, pids: [0x0C, 0x0D])
        try await fixture.record(0, 0, .responded([1]))
        XCTAssertEqual(fixture.chunks.attempts.count, 0)

        try await fixture.endSegment(.linkLost, lastReceivedAt: lastReceive)
        XCTAssertEqual(fixture.chunks.attempts.count, 1)
        try await fixture.beginSegment(cause: .linkLost, gapStartedAt: lastReceive)
        try await fixture.respondedRound(1, payload: 2)
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        let raws = fixture.chunks.committed.flatMap(\.rawEntries)
        XCTAssertEqual(raws.map(\.payload), [[1], [2]])
        XCTAssertEqual(raws.map(\.segmentOrdinal), [0, 1])
        XCTAssertEqual(raws.map(\.sequence), [0, 1])
        XCTAssertEqual(fixture.chunks.committed.first?.batches.first?.failure, .cancelled)
    }

    /// モード切替では、前の区間が modeSwitched で閉じ、modeSwitched の区間が開き、DocCの宣言どおり欠損は記録しません。
    ///
    /// 責務: モード切替の区間の終了理由・開始理由と、欠損0件、切替前の記録のcommitを確認します。
    func testModeSwitchClosesAndOpensSegmentWithoutGap() async throws {
        let segments = AcquisitionSegmentRepositorySpy()
        let gaps = AcquisitionGapRepositorySpy()
        let fixture = try Fixture(gapRepository: gaps, segmentRepository: segments)
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 1)
        fixture.dates.set(resumedAt)

        try await fixture.recorder.switchMode(generation: 1)

        let stored = try segments.segments(for: fixture.sessionID)
        XCTAssertEqual(stored.map(\.endReason), [.modeSwitched, nil])
        XCTAssertEqual(stored.map(\.startReason), [.initial, .modeSwitched])
        XCTAssertEqual(stored.last?.firstSequence, 1)
        XCTAssertEqual(stored.first?.endedAt, resumedAt)
        XCTAssertEqual(try gaps.gaps(for: fixture.sessionID), [])
        XCTAssertEqual(fixture.chunks.attempts.count, 1)
    }

    /// 区間が閉じている間は周回を記録できず、閉じた区間を再び閉じることも、開いた区間を再び開くこともできません。
    ///
    /// 責務: 区間の開閉状態に合わない呼び出しを入力不正として拒否することを確認します。
    func testCallsThatDoNotMatchSegmentStateAreRejected() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        await assertError(.invalidInput) { try await fixture.beginSegment(cause: .linkLost, gapStartedAt: self.lastReceive) }
        try await fixture.endSegment(.linkLost, lastReceivedAt: lastReceive)

        await assertError(.invalidInput) { try await fixture.beginRound(0) }
        await assertError(.invalidInput) { try await fixture.endSegment(.linkLost, lastReceivedAt: self.lastReceive) }
        await assertError(.invalidInput) { try await fixture.recorder.switchMode(generation: 1) }
        await assertError(.inactiveGeneration) { try await fixture.recorder.endSegment(generation: 2, reason: .linkLost, lastReceivedAt: self.lastReceive) }
    }

    /// 区間が閉じたまま終了すると、区間を閉じ直さずに終わります。
    ///
    /// 責務: 回復中の終了で区間の終了が1回だけになることを確認します。
    func testFinishWhileSegmentClosedDoesNotCloseAgain() async throws {
        let segments = AcquisitionSegmentRepositorySpy()
        let fixture = try Fixture(segmentRepository: segments)
        try await fixture.start()
        try await fixture.endSegment(.responseStall, lastReceivedAt: lastReceive)

        try await fixture.recorder.finish(generation: 1, reason: .vehicleNoResponse)

        let stored = try segments.segments(for: fixture.sessionID)
        XCTAssertEqual(stored.map(\.endReason), [.responseStall])
        XCTAssertEqual(stored.first?.endedAt, max(lastReceive, Fixture.startDate))
    }

    /// 区間の終了・開始、欠損の保存・終了のいずれかに失敗すると保存失敗になり、以後の記録も保存失敗です。
    ///
    /// 責務: 区間切替の各保存の失敗を成功扱いしないことを確認します。
    func testSwitchStorageFailuresReturnStorageFailed() async throws {
        let closing = try Fixture(segmentRepository: AcquisitionSegmentRepositorySpy(failsFinish: true))
        try await closing.start()
        await assertError(.storageFailed) { try await closing.endSegment(.linkLost, lastReceivedAt: self.lastReceive) }
        await assertError(.storageFailed) { try await closing.beginRound(0) }

        let cases: [Fixture] = [
            try Fixture(gapRepository: AcquisitionGapRepositorySpy(failsSave: true)),
            try Fixture(gapRepository: AcquisitionGapRepositorySpy(failsFinish: true)),
            try Fixture(segmentRepository: AcquisitionSegmentRepositorySpy(failingBeginsAfter: 1))
        ]
        for fixture in cases {
            try await fixture.start()
            try await fixture.endSegment(.linkLost, lastReceivedAt: lastReceive)
            await assertError(.storageFailed) { try await fixture.beginSegment(cause: .linkLost, gapStartedAt: self.lastReceive) }
            await assertError(.storageFailed) { try await fixture.beginRound(0) }
        }
    }

    /// 区間を切り替えて復帰し、区間・欠損の記録内容を検証します。
    ///
    /// 責務: 最後の受信より後の実時刻で区間を閉じ、再開の実時刻で次の区間を開き、記録内容を確認します。
    /// - Parameters:
    ///   - reason: 区間の終了理由。
    ///   - cause: 欠損の原因。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    private func assertResumption(
        reason: ConnectionSessionSegmentEndReason,
        cause: ConnectionSessionGapCause,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let segments = AcquisitionSegmentRepositorySpy()
        let gaps = AcquisitionGapRepositorySpy()
        let fixture = try Fixture(gapRepository: gaps, segmentRepository: segments)
        try await fixture.start()
        fixture.dates.set(lastReceive)
        try await fixture.respondedRound(0, payload: 1)
        fixture.dates.set(Date(timeIntervalSince1970: 1_013))
        try await fixture.endSegment(reason, lastReceivedAt: lastReceive)
        fixture.dates.set(resumedAt)

        try await fixture.beginSegment(cause: cause, gapStartedAt: lastReceive)

        let stored = try segments.segments(for: fixture.sessionID)
        XCTAssertEqual(stored.count, 2, file: file, line: line)
        XCTAssertEqual(stored.first?.endReason, reason, file: file, line: line)
        XCTAssertEqual(stored.first?.endedAt, lastReceive, file: file, line: line)
        XCTAssertEqual(stored.first?.lastSequence, 0, file: file, line: line)
        XCTAssertEqual(stored.last?.startReason, .reconnected, file: file, line: line)
        XCTAssertEqual(stored.last?.startedAt, resumedAt, file: file, line: line)
        XCTAssertEqual(stored.last?.firstSequence, 1, file: file, line: line)
        XCTAssertNil(stored.last?.endedAt, file: file, line: line)
        XCTAssertEqual(try gaps.gaps(for: fixture.sessionID), [ConnectionSessionGap(
            gapOrdinal: 0, precedingSegmentOrdinal: 0, followingSegmentOrdinal: 1,
            startedAt: lastReceive, endedAt: resumedAt, cause: cause
        )], file: file, line: line)
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
