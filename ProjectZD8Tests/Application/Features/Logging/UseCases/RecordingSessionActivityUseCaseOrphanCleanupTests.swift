import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` が、起動時と前面復帰時に、記録中でなければ前回のプロセスが残した表示の片付けを受け付けることのテストです。
///
/// 仕様: S2-2。片付けは他の操作と同じ列に並び、`waitForPendingOperations()` で完了を待てます。片付けの直後に記録が始まっても、
/// 開始は片付けの完了後に実行されます(順序: 片付け → 開始)。待機はすべて上限付きです。
@MainActor
final class RecordingSessionActivityUseCaseOrphanCleanupTests: XCTestCase {
    /// テスト中に組み立てた準備です。終了時に保留中の片付けを再開させます。
    private var harnesses: [RecordingSessionActivityUseCaseHarness] = []

    /// 責務: 保留中の片付けと開始を再開させ、残った操作を上限付きで片付けます。
    override func tearDown() async throws {
        for harness in harnesses {
            harness.activity.releaseAllHeldOrphanCleanups()
            harness.activity.releaseAllHeldStarts()
            await waitForOperations(harness)
        }
        harnesses.removeAll()
        try await super.tearDown()
    }

    /// 準備を組み立て、終了処理の対象に加えます。
    ///
    /// 責務: 前面にいる準備を返します。
    /// - Returns: 準備。
    private func makeHarness() -> RecordingSessionActivityUseCaseHarness {
        let harness = RecordingSessionActivityUseCaseHarness()
        harnesses.append(harness)
        return harness
    }

    /// 受け付けた境界操作の完了を上限付きで待ちます。
    ///
    /// 責務: 操作が終わらない場合は待ち続けず `XCTFail` で失敗させます。
    /// - Parameter harness: 準備。
    private func waitForOperations(_ harness: RecordingSessionActivityUseCaseHarness, file: StaticString = #filePath, line: UInt = #line) async {
        let useCase = harness.useCase!
        _ = await LiveTelemetryBoundedWaiter.value("境界操作の完了", file: file, line: line) { await useCase.waitForPendingOperations() }
    }

    /// 責務: 記録中でない起動で、片付けを1回受け付けることを確認します。
    func testLaunchWithoutRecordingEndsOrphanedPresentations() async {
        let harness = makeHarness()
        await harness.launch()
        XCTAssertEqual(harness.activity.calls, [.endOrphanedPresentations])
    }

    /// 責務: 記録中の起動では片付けを呼ばないことを確認します。
    func testLaunchWhileRecordingDoesNotEndOrphanedPresentations() async {
        let harness = makeHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        await harness.launch()
        XCTAssertEqual(harness.activity.endOrphanedPresentationsCount, 0)
        XCTAssertTrue(harness.activity.isPresenting)
    }

    /// 責務: 記録中でない前面復帰で、片付けを受け付け、表示は開始しないことを確認します。
    func testForegroundWithoutRecordingEndsOrphanedPresentations() async {
        let harness = makeHarness()
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.calls, [.endOrphanedPresentations])
    }

    /// 責務: 記録中でない前面復帰を重ねると、そのたびに片付けを受け付けることを確認します。
    func testEachForegroundWithoutRecordingEndsOrphanedPresentations() async {
        let harness = makeHarness()
        await harness.enterForeground()
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.endOrphanedPresentationsCount, 2)
    }

    /// 責務: 記録中で表示が出ている前面復帰では、片付けも開始もしないことを確認します。
    func testForegroundWhilePresentingDoesNotEndOrphanedPresentations() async {
        let harness = makeHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.endOrphanedPresentationsCount, 0)
        XCTAssertEqual(harness.activity.startedContents.count, 1)
    }

    /// 責務: 背面で始まった記録の前面復帰では、片付けをせず表示を開始することを確認します。
    func testForegroundWhileRecordingWithoutPresentationStartsWithoutCleanup() async {
        let harness = makeHarness()
        harness.foreground = false
        await harness.send(harness.state(.loaded, speed: 10))
        harness.foreground = true
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.endOrphanedPresentationsCount, 0)
        XCTAssertEqual(harness.activity.startedContents.count, 1)
        XCTAssertTrue(harness.activity.isPresenting)
    }

    /// 責務: 記録が終わった後の前面復帰では、終了表示の後に片付けを受け付けることを確認します(順序: 開始 → 終了 → 片付け)。
    func testForegroundAfterRecordingEndedEndsOrphanedPresentations() async {
        let harness = makeHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        await harness.send(harness.state(.idle, speed: 10))
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.calls.count, 3, "\(harness.activity.calls)")
        XCTAssertEqual(harness.activity.calls.last, .endOrphanedPresentations)
        XCTAssertEqual(harness.activity.endedContents.count, 1)
    }

    /// 責務: 片付けが終わるまで `waitForPendingOperations()` は戻らず、片付けの完了後に戻ることを確認します。
    func testWaitForPendingOperationsWaitsForCleanup() async {
        let harness = makeHarness()
        harness.activity.holdsOrphanCleanup = true
        harness.useCase.appDidLaunch()
        await LiveTelemetryBoundedWaiter.waitUntil("片付けの保留") { harness.activity.heldOrphanCleanupCount == 1 }
        let finished = LiveTelemetryAsyncResultBox<Bool>()
        let useCase = harness.useCase!
        let waiting = Task { await useCase.waitForPendingOperations(); finished.set(true) }
        await LiveTelemetryBoundedWaiter.settle(polls: 5)
        XCTAssertFalse(finished.isSet, "片付けの完了前に待ちが戻った")

        harness.activity.releaseAllHeldOrphanCleanups()

        await LiveTelemetryBoundedWaiter.waitUntil("片付けの完了後の待ちの終了") { finished.isSet }
        waiting.cancel()
    }

    /// 責務: 起動直後(片付けの最中)に記録が始まっても、開始は片付けの完了後に実行され、新しい表示が閉じられないことを確認します。
    func testRecordingStartedDuringCleanupStartsAfterCleanup() async {
        let harness = makeHarness()
        harness.activity.holdsOrphanCleanup = true
        harness.useCase.appDidLaunch()
        await LiveTelemetryBoundedWaiter.waitUntil("片付けの保留") { harness.activity.heldOrphanCleanupCount == 1 }
        harness.useCase.telemetryStateDidChange(harness.state(.loaded, speed: 10))
        await LiveTelemetryBoundedWaiter.settle(polls: 5)
        XCTAssertEqual(harness.activity.startedContents, [], "片付けの完了前に開始を送らない")

        harness.activity.releaseAllHeldOrphanCleanups()
        await waitForOperations(harness)

        XCTAssertEqual(harness.activity.calls.first, .endOrphanedPresentations)
        XCTAssertEqual(harness.activity.calls.count, 2, "\(harness.activity.calls)")
        XCTAssertEqual(harness.activity.startedContents.count, 1)
        XCTAssertTrue(harness.activity.isPresenting, "片付けが新しい表示を閉じた")
    }

    /// 責務: 起動と記録の開始を続けて渡すと、境界へ「片付け → 開始」の順で届くことを確認します。
    func testLaunchThenRecordingStartRunsCleanupBeforeStart() async {
        let harness = makeHarness()
        harness.useCase.appDidLaunch()
        await harness.send(harness.state(.loaded, speed: 10))
        XCTAssertEqual(harness.activity.calls.count, 2, "\(harness.activity.calls)")
        XCTAssertEqual(harness.activity.calls.first, .endOrphanedPresentations)
        XCTAssertEqual(harness.activity.startedContents.count, 1)
        XCTAssertTrue(harness.activity.isPresenting)
    }
}
