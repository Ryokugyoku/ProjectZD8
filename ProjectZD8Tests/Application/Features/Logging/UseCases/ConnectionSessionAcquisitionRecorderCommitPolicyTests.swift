import Foundation
import XCTest
@testable import ProjectZD8

/// 取得記録が件数上限・経過時間・flush契機でだけチャンクをcommitすることを検証します。
///
/// 件数は commit 方針へ渡す「保存待ちバッファの件数」で、Raw件数と終端済みbatch件数の和として数えます。
@MainActor
final class ConnectionSessionAcquisitionRecorderCommitPolicyTests: XCTestCase {
    /// 型名を短く参照するための別名です。
    private typealias Fixture = ConnectionSessionAcquisitionRecorderFixture

    /// 件数上限に達するまでcommitされず、達した時点で1回だけcommitされます。
    ///
    /// 責務: Raw 1件と終端済みbatch 1件を積む周回を繰り返し、上限の1件前とちょうど上限、上限の直後のcommit回数を確認します。
    func testCommitHappensOnceWhenBufferedCountReachesLimit() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        let limit = AcquisitionChunkCommitPolicy.bufferedCountLimit
        XCTAssertTrue(limit.isMultiple(of: 2), "周回あたり2件で上限ちょうどに達する前提")
        let lastRound = Int64(limit / 2 - 1)
        for ordinal in 0..<lastRound {
            try await fixture.respondedRound(ordinal, payload: UInt8(truncatingIfNeeded: ordinal))
        }
        try await fixture.beginRound(lastRound)
        try await fixture.record(lastRound, 0, .responded([1]))
        XCTAssertEqual(fixture.chunks.attempts.count, 0, "上限の1件前")

        try await fixture.finishRound(lastRound)

        XCTAssertEqual(fixture.chunks.attempts.count, 1)
        XCTAssertEqual(fixture.chunks.attempts.first?.rawEntries.count, limit / 2)
        XCTAssertEqual(fixture.chunks.attempts.first?.batches.count, limit / 2)
        try await fixture.beginRound(lastRound + 1)
        try await fixture.record(lastRound + 1, 0, .responded([2]))
        XCTAssertEqual(fixture.chunks.attempts.count, 1, "上限の直後")
    }

    /// 前回commitから経過上限以上たった後の次の受信でcommitされ、時計を進めただけではcommitされません。
    ///
    /// 責務: 経過上限の1ナノ秒前の受信、受信なしの経過、上限以上での受信のcommit回数と内容を確認します。
    func testElapsedLimitCommitsOnNextReceiveOnly() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 1)
        fixture.clock.advance(byNanoseconds: AcquisitionChunkCommitPolicy.elapsedLimitNanoseconds - 1)
        try await fixture.beginRound(1, pids: [0x0C, 0x0D])
        try await fixture.record(1, 0, .responded([2]))
        XCTAssertEqual(fixture.chunks.attempts.count, 0, "経過上限の1ナノ秒前")

        fixture.clock.advance(byNanoseconds: 1 + 10 * AcquisitionChunkCommitPolicy.elapsedLimitNanoseconds)
        XCTAssertEqual(fixture.chunks.attempts.count, 0, "受信なし")
        try await fixture.record(1, 1, pid: 0x0D, .responded([3]))

        XCTAssertEqual(fixture.chunks.attempts.count, 1)
        XCTAssertEqual(fixture.chunks.attempts.first?.batches.map(\.identity.ordinal), [0])
        try await fixture.finishRound(1)
        XCTAssertEqual(fixture.chunks.attempts.count, 1, "commit直後は経過が0に戻る")
    }

    /// セグメント終了・セッション終了・バックグラウンド移行のflushは、件数・経過にかかわらずcommitします。
    ///
    /// 責務: 上限未満・経過0の終端済み周回が、3つの契機それぞれで1回commitされることを確認します。
    func testEachFlushTriggerCommitsRegardlessOfCountAndElapsed() async throws {
        let triggers: [LiveTelemetryAcquisitionFlushTrigger] = [.segmentEnded, .sessionEnded, .backgroundTransition]
        for trigger in triggers {
            let fixture = try Fixture()
            try await fixture.start()
            try await fixture.respondedRound(0, payload: 1)
            XCTAssertEqual(fixture.chunks.attempts.count, 0, "\(trigger)")

            try await fixture.recorder.flush(trigger, generation: 1)

            XCTAssertEqual(fixture.chunks.attempts.count, 1, "\(trigger)")
            XCTAssertEqual(fixture.chunks.attempts.first?.batches.map(\.identity.ordinal), [0], "\(trigger)")
        }
    }

    /// 取得の終了は件数・経過にかかわらず保存待ちをcommitします。
    ///
    /// 責務: 上限未満・経過0の終端済み周回が `finish` で1回commitされることを確認します。
    func testFinishCommitsPendingRegardlessOfCountAndElapsed() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        try await fixture.respondedRound(0, payload: 1)

        try await fixture.recorder.finish(generation: 1, reason: .userDisconnected)

        XCTAssertEqual(fixture.chunks.attempts.count, 1)
        XCTAssertEqual(fixture.chunks.attempts.first?.rawEntries.map(\.payload), [[1]])
    }

    /// 保存待ちが無い、または未完了の周回しか無い場合のflushはcommitしません。
    ///
    /// 責務: 空のチャンクと未完了batchだけのチャンクを保存しないことを確認します。
    func testFlushWithoutTerminalBatchDoesNotCommit() async throws {
        let fixture = try Fixture()
        try await fixture.start()
        try await fixture.recorder.flush(.backgroundTransition, generation: 1)
        try await fixture.beginRound(0)
        try await fixture.record(0, 0, .responded([1]))

        try await fixture.recorder.flush(.backgroundTransition, generation: 1)

        XCTAssertEqual(fixture.chunks.attempts.count, 0)
    }
}
