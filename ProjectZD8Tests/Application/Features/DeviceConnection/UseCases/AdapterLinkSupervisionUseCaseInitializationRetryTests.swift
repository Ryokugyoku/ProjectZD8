import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` の初期化失敗後の5秒再試行(S1-2)の予約・発火・取り消しを、fake の時計で検証します。
///
/// 待機はすべて `BLEBoundedWaiter` の回数上限付きで、上限を超えたら `XCTFail` します。
@MainActor
final class AdapterLinkSupervisionUseCaseInitializationRetryTests: XCTestCase {
    /// テスト中に組み立てた手段です。終了時に保留を終わらせます。
    private var harnesses: [AdapterLinkSupervisionHarness] = []

    /// 責務: 保留中の非同期呼び出しを全て終わらせます。
    override func tearDown() async throws {
        harnesses.forEach { $0.finishAllPending() }
        harnesses.removeAll()
        try await super.tearDown()
    }

    /// 責務: 手段を組み立て、終了処理の対象に加えます。
    private func makeHarness() -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness()
        harnesses.append(harness)
        return harness
    }

    /// 初期化を1回失敗させ、5秒の再試行の待機が予約されるところまで進めます。
    ///
    /// 責務: リンク `ready` から初期化の失敗を返し、待機が1件要求されるまで待ちます。
    private func driveToScheduledRetry(_ harness: AdapterLinkSupervisionHarness, file: StaticString = #filePath, line: UInt = #line) async throws {
        harness.startSignedIn()
        try await harness.makeLinkReady(file: file, line: line)
        harness.initialization.responses.resumeOldest(with: .failure(AdapterLinkWriteError.linkLost), file: file, line: line)
        try await harness.wait("再試行の予約", file: file, line: line) { harness.clock.requestedDurations.count == 1 }
    }

    /// 予約が取り消されたあと、待機が明けても初期化が呼ばれないことを検証します。
    ///
    /// 責務: 古い待機を終わらせて十分に待ち、初期化の呼び出しが増えないことを確認します。
    private func assertRetryDoesNotFire(
        _ harness: AdapterLinkSupervisionHarness, callsBefore: Int, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        harness.clock.finishOldestSleep(advancingBy: 5, file: file, line: line)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, callsBefore, file: file, line: line)
    }

    /// 初期化に失敗したら5秒の予約が入り、待機が明けると再初期化が1回呼ばれます(仕様1)。
    ///
    /// 責務: 予約の時間・待機明け前に呼ばれないこと・待機明けで1回だけ呼ばれて初期化中になることを確認します。
    func testInitializationFailureSchedulesRetryThatReinitializesOnce() async throws {
        let harness = makeHarness()
        try await driveToScheduledRetry(harness)
        XCTAssertEqual(harness.clock.requestedDurations, [.seconds(5)])
        XCTAssertEqual(harness.useCase.state, .standby)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 1)

        harness.clock.finishOldestSleep(advancingBy: 5)
        try await harness.wait("再初期化") { harness.initialization.responses.callCount == 2 }
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// 再初期化も失敗したら、もう一度5秒後の再試行を予約します(上限付きで2周)。
    ///
    /// 責務: 失敗のたびに5秒の予約が増え、待機明けごとに初期化が1回ずつ増えることを確認します。
    func testRepeatedFailuresKeepSchedulingRetries() async throws {
        let harness = makeHarness()
        try await driveToScheduledRetry(harness)
        for round in 2...3 {
            harness.clock.finishOldestSleep(advancingBy: 5)
            try await harness.wait("\(round)回目の初期化") { harness.initialization.responses.callCount == round }
            harness.initialization.responses.resumeOldest(with: .failure(AdapterLinkWriteError.linkLost))
            try await harness.wait("\(round)回目の予約") { harness.clock.requestedDurations.count == round }
            XCTAssertEqual(harness.clock.requestedDurations.last, .seconds(5))
        }
    }

    /// リンク断で予約が取り消され、待機が明けても初期化は呼ばれません(仕様2)。
    ///
    /// 責務: 切断後に古い待機を終わらせても初期化の呼び出しが増えないことを確認します。
    func testLinkLossCancelsRetry() async throws {
        let harness = makeHarness()
        try await driveToScheduledRetry(harness)
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await assertRetryDoesNotFire(harness, callsBefore: 1)
    }

    /// 手動接続の開始で予約が取り消され、待機が明けても初期化は呼ばれません(仕様2)。
    ///
    /// 責務: 手動使用中に古い待機を終わらせても初期化の呼び出しが増えないことを確認します。
    func testExternalAdapterUseBeginCancelsRetry() async throws {
        let harness = makeHarness()
        try await driveToScheduledRetry(harness)
        harness.useCase.externalAdapterUseDidBegin()
        try await assertRetryDoesNotFire(harness, callsBefore: 1)
    }

    /// 監視の停止で予約が取り消され、待機が明けても初期化は呼ばれません(仕様2)。
    ///
    /// 責務: `stop()` の後に古い待機を終わらせても初期化の呼び出しが増えないことを確認します。
    func testStopCancelsRetry() async throws {
        let harness = makeHarness()
        try await driveToScheduledRetry(harness)
        harness.useCase.stop()
        try await assertRetryDoesNotFire(harness, callsBefore: 1)
    }

    /// 予約中に前面復帰で先に初期化へ入ったら、待機が明けても初期化は二重になりません(仕様2)。
    ///
    /// 責務: 前面復帰で初期化が2回目になり、古い待機を終わらせても3回目が呼ばれないことを確認します。
    func testForegroundDuringRetryWaitDoesNotDoubleInitialize() async throws {
        let harness = makeHarness()
        try await driveToScheduledRetry(harness)
        harness.useCase.appDidBecomeActive()
        try await harness.wait("前面復帰での初期化") { harness.initialization.responses.callCount == 2 }
        try await assertRetryDoesNotFire(harness, callsBefore: 2)
    }

    /// 取り消された古い予約が、のちの新しい予約より先に発火して再初期化を早めないことを検証します。
    ///
    /// 責務: 契機のあとで再び初期化に入って失敗させ、新しい予約(2件目の待機)が入った状態で、古い待機(1件目)が明けても
    /// 初期化が呼ばれず、新しい待機が明けたときだけ1回呼ばれることを確認します。
    private func assertStaleRetryDoesNotFireBeforeNewOne(
        after trigger: (AdapterLinkSupervisionHarness) async throws -> Void, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let harness = makeHarness()
        try await driveToScheduledRetry(harness, file: file, line: line)
        try await trigger(harness)
        try await harness.wait("契機後の初期化", file: file, line: line) { harness.initialization.responses.callCount == 2 }
        harness.initialization.responses.resumeOldest(with: .failure(AdapterLinkWriteError.linkLost), file: file, line: line)
        try await harness.wait("新しい予約", file: file, line: line) { harness.clock.requestedDurations.count == 2 }

        harness.clock.finishOldestSleep(advancingBy: 5, file: file, line: line)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 2, "古い予約が発火した", file: file, line: line)

        harness.clock.finishOldestSleep(advancingBy: 5, file: file, line: line)
        try await harness.wait("新しい予約での初期化", file: file, line: line) { harness.initialization.responses.callCount == 3 }
    }

    /// リンク断・再接続のあと、古い予約は新しい予約より先に発火しません(仕様2)。
    func testStaleRetryAfterLinkLossDoesNotFireEarly() async throws {
        try await assertStaleRetryDoesNotFireBeforeNewOne { harness in
            harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
            try await harness.makeLinkReady()
        }
    }

    /// 手動接続の開始・終了のあと、古い予約は新しい予約より先に発火しません(仕様2・4)。
    func testStaleRetryAfterExternalAdapterUseDoesNotFireEarly() async throws {
        try await assertStaleRetryDoesNotFireBeforeNewOne { harness in
            harness.useCase.externalAdapterUseDidBegin()
            harness.useCase.externalAdapterUseDidEnd()
        }
    }

    /// 停止・再開始のあと、古い予約は新しい予約より先に発火しません(仕様2)。
    func testStaleRetryAfterStopAndStartDoesNotFireEarly() async throws {
        try await assertStaleRetryDoesNotFireBeforeNewOne { harness in
            harness.useCase.stop()
            harness.useCase.start()
            try await harness.makeLinkReady()
        }
    }
}
