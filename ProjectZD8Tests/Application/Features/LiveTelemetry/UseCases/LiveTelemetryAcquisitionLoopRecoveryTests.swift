import Foundation
import XCTest
@testable import ProjectZD8

/// 取得ループの途絶の検知と、プロンプト再同期→ATZ再初期化→再接続の段階的回復を検証します。
@MainActor
final class LiveTelemetryAcquisitionLoopRecoveryTests: XCTestCase {
    /// 各テストのループ部品です。
    private var fixture: LiveTelemetryAcquisitionLoopFixture?

    /// 動いている取得を止め、期限待ちを解放します。
    ///
    /// 責務: テストごとに応答待ちの要求・期限待ち・取得Taskを片付けます。
    override func tearDown() async throws {
        await fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// 最後の正応答から途絶閾値未満では回復に入らず、閾値以上で次の結果を受けた時に応答途絶として回復に入ります。
    ///
    /// 責務: 閾値の1ナノ秒前と閾値ちょうどのタイムアウトで、回復操作と区間終了の有無を確認します。
    func testStallThresholdBoundaryEntersRecovery() async {
        let fixture = make()
        _ = await fixture.start(definitions: [LiveTelemetryTestDefinitions.standard(0x0C)])
        await fixture.telemetry.release(.responded([1]))
        await fixture.telemetry.waitForSentRequests(2)
        fixture.clock.advance(byNanoseconds: AcquisitionStallPolicy.stallThresholdNanoseconds - 1)
        await fixture.telemetry.release(.timedOut)
        await fixture.telemetry.waitForSentRequests(3)
        XCTAssertEqual(fixture.linkRecovery.calls, [], "閾値の1ナノ秒前")

        fixture.clock.advance(byNanoseconds: 1)
        await fixture.telemetry.release(.timedOut)
        await fixture.linkRecovery.waitForCalls(1)

        XCTAssertEqual(fixture.linkRecovery.calls.first, .promptResync)
        let segments = await fixture.recorder?.segmentCalls
        XCTAssertEqual(segments, [.endSegment(generation: 1, reason: .responseStall, lastReceivedAt: LiveTelemetryAcquisitionLoopFixture.fixedNow)])
    }

    /// 通信失敗は経過にかかわらず、リンク断として回復に入ります。
    ///
    /// 責務: 時計を進めない通信失敗で区間が linkLost で閉じられ、回復操作が始まることを確認します。
    func testTransportFailureEntersRecoveryImmediately() async {
        let fixture = make()
        _ = await fixture.start(definitions: [LiveTelemetryTestDefinitions.standard(0x0C)])
        await fixture.telemetry.release(.responded([1]))

        await fixture.telemetry.release(.transportFailure)
        await fixture.linkRecovery.waitForCalls(1)

        let segments = await fixture.recorder?.segmentCalls
        XCTAssertEqual(segments?.first, .endSegment(generation: 1, reason: .linkLost, lastReceivedAt: LiveTelemetryAcquisitionLoopFixture.fixedNow))
    }

    /// 全段階が失敗すると、各段階を上限回数ずつ順に試してから一時停止に入り、それ以上は試しません。
    ///
    /// 責務: 呼び出し列・合計回数が上限の合計と一致すること、報告されたフェーズ列、一時停止後に回復操作が増えないことを確認します。
    func testAllStagesFailInOrderUpToLimitsThenPause() async {
        let fixture = make()
        let (collector, _) = await fixture.startAndPause(cause: .linkLost)
        await LiveTelemetryBoundedWaiter.settle(polls: 100)

        let expected = Array(repeating: AcquisitionRecoveryStage.promptResync, count: AcquisitionStallPolicy.promptResyncAttemptLimit)
            + Array(repeating: .reinitializeFromReset, count: AcquisitionStallPolicy.reinitializeFromResetAttemptLimit)
            + Array(repeating: .reconnectLink, count: AcquisitionStallPolicy.reconnectLinkAttemptLimit)
        XCTAssertEqual(fixture.linkRecovery.calls, expected)
        XCTAssertEqual(fixture.linkRecovery.calls.count, 3 + 2 + 3)
        let recovering = collector.phases.compactMap { phase -> String? in
            if case let .recovering(_, stage, attempt) = phase { "\(stage)#\(attempt)" } else { nil }
        }
        XCTAssertEqual(recovering, [
            "promptResync#1", "promptResync#2", "promptResync#3", "reinitializeFromReset#1", "reinitializeFromReset#2",
            "reconnectLink#1", "reconnectLink#2", "reconnectLink#3"
        ])
        XCTAssertEqual(collector.phases.last, .paused(cause: .linkLost))
        XCTAssertNil(collector.termination)
    }

    /// 1段階目の1回目で成功すれば取得を再開し、以降の段階は呼ばれません。
    ///
    /// 責務: 回復操作の成功と確認要求の正応答で再開することを確認します。
    func testFirstAttemptSuccessResumes() async {
        await assertResumes(after: [true], expectedCalls: [.promptResync])
    }

    /// 1段階目の途中で成功すれば取得を再開します。
    ///
    /// 責務: 1段階目の2回目の成功で再開し、2段階目へ進まないことを確認します。
    func testSuccessMidFirstStageResumes() async {
        await assertResumes(after: [false, true], expectedCalls: [.promptResync, .promptResync])
    }

    /// 2段階目で成功すれば取得を再開します。
    ///
    /// 責務: 1段階目を使い切った後のATZ再初期化の成功で再開することを確認します。
    func testSecondStageSuccessResumes() async {
        await assertResumes(after: [false, false, false, true], expectedCalls: [.promptResync, .promptResync, .promptResync, .reinitializeFromReset])
    }

    /// 3段階目で成功すれば取得を再開します。
    ///
    /// 責務: 2段階目までを使い切った後の再接続の成功で再開することを確認します。
    func testThirdStageSuccessResumes() async {
        await assertResumes(
            after: [false, false, false, false, false, true],
            expectedCalls: [.promptResync, .promptResync, .promptResync, .reinitializeFromReset, .reinitializeFromReset, .reconnectLink]
        )
    }

    /// 回復操作が成功しても確認の要求が無応答なら失敗として数え、次の試行へ進みます。
    ///
    /// 責務: 確認要求のタイムアウトで再開せず、次の試行の確認要求の正応答で再開することと、確認要求を記録しないことを確認します。
    func testProbeWithoutResponseCountsAsFailure() async {
        let fixture = make()
        fixture.linkRecovery.schedule([true, true])
        _ = await fixture.start(definitions: [LiveTelemetryTestDefinitions.standard(0x0C)])
        await fixture.telemetry.release(.responded([1]))
        await fixture.telemetry.release(.transportFailure)

        await fixture.telemetry.release(.timedOut)
        await fixture.telemetry.release(.responded([2]))
        await fixture.telemetry.waitForSentRequests(5)

        XCTAssertEqual(fixture.linkRecovery.calls, [.promptResync, .promptResync])
        let results = await fixture.recorder?.recordedResults ?? []
        XCTAssertEqual(results.map(\.outcome), [.responded([1]), .transportFailure])
        let segments = await fixture.recorder?.segmentCalls ?? []
        XCTAssertEqual(segments.count, 2)
    }

    /// 回復中にユーザーが停止すると、猶予を待たずにユーザー切断で終わります。
    ///
    /// 責務: 確認要求の応答待ち(回復中)からの停止が停止理由を返し、記録の終了理由がユーザー切断になることを確認します。
    func testStopDuringRecoveryEndsImmediately() async {
        let fixture = make()
        fixture.linkRecovery.schedule([true])
        let collector = await fixture.start(definitions: [LiveTelemetryTestDefinitions.standard(0x0C)])
        await fixture.telemetry.release(.responded([1]))
        await fixture.telemetry.release(.transportFailure)
        await fixture.telemetry.waitForSentRequests(3)

        let termination = await fixture.stopLoop()

        XCTAssertEqual(termination, .stopped)
        XCTAssertEqual(collector.phases, [.recovering(cause: .linkLost, stage: .promptResync, attempt: 1)])
        let finishes = await fixture.recorder?.finishCalls
        XCTAssertEqual(finishes, [.finish(generation: 1, reason: .userDisconnected)])
        XCTAssertEqual(fixture.deadlineWaiter.requestedDeadlines, [])
    }

    /// 予約した結果で回復させ、取得が再開されて以降の段階が呼ばれないことを検証します。
    ///
    /// 責務: 通信失敗で回復に入り、回復操作の成功時は確認要求に正応答を返し、区間の再開・取得中への復帰・次の周回の要求を確認します。
    /// - Parameters:
    ///   - results: 回復操作へ順に返す結果。
    ///   - expectedCalls: 期待する回復段階の呼び出し列。
    ///   - file: 失敗を報告するファイル。
    ///   - line: 失敗を報告する行。
    private func assertResumes(
        after results: [Bool],
        expectedCalls: [AcquisitionRecoveryStage],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let fixture = make()
        fixture.linkRecovery.schedule(results)
        let collector = await fixture.start(definitions: [LiveTelemetryTestDefinitions.standard(0x0C)])
        await fixture.telemetry.release(.responded([1]), file: file, line: line)
        await fixture.telemetry.release(.transportFailure, file: file, line: line)

        await fixture.telemetry.release(.responded([2]), file: file, line: line)
        await fixture.telemetry.waitForSentRequests(4, file: file, line: line)
        await LiveTelemetryBoundedWaiter.settle(polls: 50)

        XCTAssertEqual(fixture.linkRecovery.calls, expectedCalls, file: file, line: line)
        XCTAssertEqual(collector.phases.last, .acquiring, file: file, line: line)
        XCTAssertNil(collector.termination, file: file, line: line)
        let segments = await fixture.recorder?.segmentCalls
        XCTAssertEqual(segments, [
            .endSegment(generation: 1, reason: .linkLost, lastReceivedAt: LiveTelemetryAcquisitionLoopFixture.fixedNow),
            .beginSegment(.init(generation: 1, startReason: .reconnected, gapCause: .linkLost, gapStartedAt: LiveTelemetryAcquisitionLoopFixture.fixedNow))
        ], file: file, line: line)
        let rounds = await fixture.recorder?.roundInputs ?? []
        XCTAssertEqual(rounds.map(\.batchOrdinal), [0, 1, 2], file: file, line: line)
    }

    /// 記録ポートのスパイ付きの部品を生成して後片付けの対象にします。
    ///
    /// 責務: 既定の記録ポートを持つループ部品を返します。
    /// - Returns: ループ部品。
    private func make() -> LiveTelemetryAcquisitionLoopFixture {
        let fixture = LiveTelemetryAcquisitionLoopFixture()
        self.fixture = fixture
        return fixture
    }
}
