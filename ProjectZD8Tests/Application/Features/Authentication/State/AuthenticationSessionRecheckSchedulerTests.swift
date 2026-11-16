import XCTest
@testable import ProjectZD8

/// `AuthenticationSessionRecheckScheduler` が判定の待ち時間ごとに上限まで再確認し、解決・取り消しで止まり、始め直しで回数を取り直すことを、
/// 手動で進める待機の Fake で検証します(待機はすべて上限付き)。
///
/// 仕様: U5 受け入れ条件 15・16。
@MainActor
final class AuthenticationSessionRecheckSchedulerTests: XCTestCase {
    /// 待機の Fake です。
    private var sleeper: AuthenticationRecheckSleepFake!
    /// 検証対象です。
    private var scheduler: AuthenticationSessionRecheckScheduler!
    /// 再確認が呼ばれた回数です。
    private var recheckCount = 0
    /// 再確認が返す結果です(呼ばれるたびに先頭から使い、尽きたら `.unresolved`)。
    private var outcomes: [AuthenticationSessionRecheckScheduler.Outcome] = []

    /// 責務: 既定の判定と待機の Fake で検証対象を作ります。
    override func setUp() async throws {
        try await super.setUp()
        sleeper = AuthenticationRecheckSleepFake()
        scheduler = AuthenticationSessionRecheckScheduler(policy: .standard, sleep: sleeper.sleep)
        recheckCount = 0
        outcomes = []
    }

    /// 責務: 列を取り消し、残った待機を終わらせます。
    override func tearDown() async throws {
        scheduler?.cancel()
        sleeper?.drain()
        scheduler = nil
        sleeper = nil
        try await super.tearDown()
    }

    /// 1回の再確認です。
    ///
    /// 責務: 呼ばれた回数を数え、台本の結果を返します。
    /// - Returns: 台本の先頭、尽きたら `.unresolved`。
    private func recheck() async -> AuthenticationSessionRecheckScheduler.Outcome {
        recheckCount += 1
        return outcomes.isEmpty ? .unresolved : outcomes.removeFirst()
    }

    /// 列を始めます。
    ///
    /// 責務: 再確認の処理をこのテストの `recheck()` へ結び付けて始めます。
    /// - Parameter immediately: 待たずに1回再確認するか。
    private func start(immediately: Bool) {
        scheduler.start(immediately: immediately) { [weak self] in await self?.recheck() ?? .resolved }
    }

    /// 指定件数の待機が要求されるまで上限付きで待ちます。
    ///
    /// 責務: 要求件数の到達を待ち、上限内に届かなければ失敗させて throw し、以降の手順(繰り返しを含む)を打ち切ります。
    /// - Parameter count: 待つ要求件数。
    /// - Throws: 上限内に届かなかった場合は `AdapterLinkBoundedAwaitTimeout`。
    private func waitForSleeps(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        guard try await BLEBoundedWaiter.waitUntil("待機 \(count) 件", file: file, line: line, condition: {
            sleeper.requestedDurations.count >= count
        }) else { throw AdapterLinkBoundedAwaitTimeout(description: "待機 \(count) 件") }
    }

    /// 列が止まるまで上限付きで待ちます。
    ///
    /// 責務: `isRunning` が偽になるのを待ちます。
    private func waitUntilStopped(file: StaticString = #filePath, line: UInt = #line) async throws {
        try await BLEBoundedWaiter.waitUntil("列の停止", file: file, line: line) { !scheduler.isRunning }
    }

    /// 確認できないままなら、5・15・60・60…秒の待ちの後に合計10回再確認して止まります。
    ///
    /// 責務: 待ちの列・再確認の回数・上限の後に待機が増えず止まることを確認します(受け入れ条件 15)。
    func testUnresolvedRechecksTenTimesWithPolicyDelays() async throws {
        start(immediately: false)
        XCTAssertTrue(scheduler.isRunning)
        for attempt in 1...10 {
            try await waitForSleeps(attempt)
            XCTAssertEqual(recheckCount, attempt - 1, "待ちの前に再確認しない")
            guard sleeper.finishOldest() else { return XCTFail("\(attempt)回目: 保留中の待機が無いため打ち切り") }
            guard try await BLEBoundedWaiter.waitUntil("\(attempt)回目の再確認", condition: { recheckCount == attempt }) else { return }
        }
        try await waitUntilStopped()

        let expected: [Duration] = [.seconds(5), .seconds(15), .seconds(60)] + Array(repeating: .seconds(60), count: 7)
        XCTAssertEqual(sleeper.requestedDurations, expected)
        XCTAssertEqual(recheckCount, 10)
        XCTAssertEqual(sleeper.pendingCount, 0, "上限の後に待たない")
    }

    /// 確認できた(解決した)ら、その時点で再確認をやめます。
    ///
    /// 責務: 2回目で解決すると、待機が2件・再確認が2回で止まることを確認します。
    func testResolvedOutcomeStopsRechecking() async throws {
        outcomes = [.unresolved, .resolved]
        start(immediately: false)
        try await waitForSleeps(1)
        sleeper.finishOldest()
        try await waitForSleeps(2)
        sleeper.finishOldest()
        try await waitUntilStopped()

        XCTAssertEqual(recheckCount, 2)
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5), .seconds(15)])
    }

    /// 即時の指定では待たずに1回再確認し、その1回は回数に数えず、確認できなければ5秒から始めます。
    ///
    /// 責務: 待機0件のまま再確認1回、続く待機が5秒であることを確認します(受け入れ条件 15 (a))。
    func testImmediateRecheckIsNotCounted() async throws {
        start(immediately: true)
        try await waitForSleeps(1)
        XCTAssertEqual(recheckCount, 1, "待機の前に即時の再確認が1回")
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5)])
        sleeper.finishOldest()
        try await waitForSleeps(2)
        XCTAssertEqual(sleeper.requestedDurations, [.seconds(5), .seconds(15)], "即時の1回を数えず、1回目の待ちから始める")
    }

    /// 即時の再確認で解決すれば、待たずに止まります。
    ///
    /// 責務: 再確認1回・待機0件で止まることを確認します。
    func testImmediateResolvedStopsWithoutWaiting() async throws {
        outcomes = [.resolved]
        start(immediately: true)
        try await waitUntilStopped()
        XCTAssertEqual(recheckCount, 1)
        XCTAssertEqual(sleeper.requestedDurations, [])
    }

    /// 取り消すと、待機中の列は止まり、以後再確認しません。
    ///
    /// 責務: 1件目の待機中の取り消しで `isRunning` が偽になり、待機が取り消しで終わり、再確認が0回のままであることを確認します(受け入れ条件 16)。
    func testCancelStopsWaitingSeries() async throws {
        start(immediately: false)
        try await waitForSleeps(1)

        scheduler.cancel()

        XCTAssertFalse(scheduler.isRunning)
        try await BLEBoundedWaiter.waitUntil("待機の取り消し") { sleeper.cancelledIndices.contains(0) }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(recheckCount, 0)
        XCTAssertEqual(sleeper.requestedDurations.count, 1)
    }

    /// 始め直すと、動いている列を取り消して回数を0から取り直します。
    ///
    /// 責務: 3回再確認した後の始め直しで、次の待機が再び5秒になり、古い列の待機は取り消されることを確認します(受け入れ条件 15 の取り直し)。
    func testRestartResetsAttemptCount() async throws {
        start(immediately: false)
        for attempt in 1...3 {
            try await waitForSleeps(attempt)
            guard sleeper.finishOldest() else { return XCTFail("\(attempt)回目: 保留中の待機が無いため打ち切り") }
            guard try await BLEBoundedWaiter.waitUntil("\(attempt)回目", condition: { recheckCount == attempt }) else { return }
        }
        try await waitForSleeps(4)
        XCTAssertEqual(sleeper.requestedDurations.last, .seconds(60))

        start(immediately: false)

        try await waitForSleeps(5)
        XCTAssertEqual(sleeper.requestedDurations.last, .seconds(5))
        try await BLEBoundedWaiter.waitUntil("古い列の待機の取り消し") { sleeper.cancelledIndices.contains(3) }
        XCTAssertTrue(scheduler.isRunning)
    }

    /// 上限まで再確認して止まった後でも、始め直せば再び再確認します。
    ///
    /// 責務: 上限0回の判定で、即時の再確認だけが行われて止まり、もう一度始めると再び1回再確認することを確認します。
    func testStartAfterStoppedRunsAgain() async throws {
        scheduler = AuthenticationSessionRecheckScheduler(
            policy: AuthenticationSessionRecheckPolicy(leadingDelays: [], repeatingDelay: .seconds(1), maximumAttempts: 0),
            sleep: sleeper.sleep
        )
        start(immediately: true)
        try await waitUntilStopped()
        XCTAssertEqual(recheckCount, 1)

        start(immediately: true)
        try await waitUntilStopped()
        XCTAssertEqual(recheckCount, 2)
        XCTAssertEqual(sleeper.requestedDurations, [])
    }
}
