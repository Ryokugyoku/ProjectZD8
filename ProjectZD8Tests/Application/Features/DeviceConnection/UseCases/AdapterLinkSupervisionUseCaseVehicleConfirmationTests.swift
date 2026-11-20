import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` の初期化・車両確認・確認窓・窓後の継続・検知通知を、fake の時計で検証します。
@MainActor
final class AdapterLinkSupervisionUseCaseVehicleConfirmationTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 窓後の待機に入るまで回す無応答サイクルの上限です。仕様の600回を十分に超える値にし、入らない不具合を失敗にします。
    private let maximumCycles = 700
    /// 1窓あたりの確認回数の上限(窓10分 ÷ 最短間隔1秒)です(U3 受け入れ条件 4)。
    private let attemptLimit = 600

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

    /// 「確認に指定秒数かかって無応答」を、窓後の間隔の待機が要求されるまで繰り返します。
    ///
    /// 責務: 時計を指定秒数進めてから保留中の確認へ無応答を返し、次の確認か待機を待ちます。最短間隔(1秒)の待ちが
    /// 要求された場合は時計を進めずに終わらせて繰り返し、それより長い待機(窓後の間隔)が要求されたらその待機を保留したまま戻ります。
    /// 上限付きで繰り返し、上限内に長い待機へ入らなければ失敗させます。
    /// 保留が無い・待ちが上限内に成り立たないなど、1周でも手順が進まなければその時点で失敗させて打ち切ります
    /// (`harness.wait` は上限超過で throw します)。
    /// - Parameters:
    ///   - harness: 車両確認が1件保留されている手段。
    ///   - seconds: 1回の確認にかかる秒数(アダプターが無応答を返すまでの時間)。
    private func runNoResponseCyclesUntilExtendedWait(
        _ harness: AdapterLinkSupervisionHarness, eachTaking seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        for _ in 0..<maximumCycles {
            let sleeps = harness.clock.requestedDurations.count
            let confirmations = harness.vehicleResponse.timeouts.count
            harness.clock.now = harness.clock.now.addingTimeInterval(seconds)
            guard harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse), file: file, line: line) else {
                return XCTFail("保留中の確認が無いため打ち切り", file: file, line: line)
            }
            try await harness.wait("次の確認か待機", file: file, line: line) {
                harness.vehicleResponse.timeouts.count > confirmations || harness.clock.requestedDurations.count > sleeps
            }
            guard harness.vehicleResponse.timeouts.count == confirmations else { continue }
            if let wait = harness.clock.requestedDurations.last, wait > .seconds(1) { return }
            guard harness.clock.finishOldestSleep(advancingBy: 0, file: file, line: line) else {
                return XCTFail("保留中の待機が無いため打ち切り", file: file, line: line)
            }
            try await harness.wait("再確認", file: file, line: line) { harness.vehicleResponse.timeouts.count > confirmations }
        }
        XCTFail("\(maximumCycles)回の無応答で窓後の待機に入らなかった", file: file, line: line)
    }

    /// 初期化成功後の最初の確認は通常のタイムアウトで1回行います。
    ///
    /// 責務: 確認ポートへ `.standard` が1回だけ渡り、確認中になることを確認します。
    func testFirstConfirmationUsesStandardTimeout() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        XCTAssertEqual(harness.vehicleResponse.timeouts, [.standard])
        XCTAssertTrue(harness.isConfirming(.probing))
    }

    /// ECU無応答(確認に最短間隔以上かかった)では通知を出さず、リンクを止めず、固定の待機を挟まずに次の確認を送ります。
    ///
    /// 責務: 通知0件・リンク停止0回・待機の要求0件・2回目の確認・確認中のままを確認します(U3 受け入れ条件 1・2)。
    func testNoResponseDoesNotNotifyAndKeepsLink() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.clock.now = harness.clock.now.addingTimeInterval(30)
        harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
        try await harness.wait("2回目の確認") { harness.vehicleResponse.timeouts.count == 2 }
        XCTAssertEqual(harness.clock.requestedDurations, [], "固定の待機を挟まない")
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.link.stopCount, 0)
        XCTAssertTrue(harness.isConfirming(.probing))
    }

    /// 2回目以降の確認は、アダプター最大タイムアウトで送ります(無応答の間の頻度はアダプター側のタイムアウトで決まる)。
    ///
    /// 責務: 2回目・3回目の確認へ `.adapterMaximum` が渡ることを確認します(U3 受け入れ条件 2)。
    func testRecheckUsesAdapterMaximumTimeout() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        for expected in [2, 3] {
            harness.clock.now = harness.clock.now.addingTimeInterval(30)
            harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
            try await harness.wait("\(expected)回目の確認") { harness.vehicleResponse.timeouts.count == expected }
        }
        XCTAssertEqual(harness.vehicleResponse.timeouts, [.standard, .adapterMaximum, .adapterMaximum])
    }

    /// 確認が失敗(throw)しても無応答と同じく再確認を予約し、検知も通知もしません。
    ///
    /// 責務: 確認失敗の後に待機が予約され、VIN読取と通知がないことを確認します。
    func testConfirmationFailureContinuesWithoutDetection() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.vehicleResponse.responses.resumeOldest(with: .failure(AdapterLinkWriteError.linkLost))
        try await harness.wait("再確認の待機") { harness.clock.requestedDurations.count == 1 }
        XCTAssertEqual(harness.vinReader.responses.callCount, 0)
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
        XCTAssertTrue(harness.isConfirming(.probing))
    }

    /// ECUが応答したら「車両を検知しました」通知をVIN付きで1回だけ提示し、記録は始めません(自動記録オフ)。
    ///
    /// 責務: 通知1件・VIN・記録開始要求なし・検知済み状態を、後続の再通知や前面復帰の後も保つことを確認します。
    func testRespondingPresentsDetectionExactlyOnce() async throws {
        let harness = makeHarness()
        try await harness.driveToAwaitingRecordingStart(vin: F.vin)
        harness.link.emit(.ready)
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [F.vin])
        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.recordingControl.startRequests, [])
        XCTAssertEqual(harness.useCase.state, .vehicleDetected(F.detectedVehicle, phase: .awaitingRecordingStart))
    }

    /// VINが読めない(`nil`)・読取が失敗しても検知は成立し、VINなしで通知します。
    ///
    /// 責務: `nil` と throw の両方で、VINなしの検知通知が1件出ることを確認します。
    func testUnreadableOrFailedVINStillDetects() async throws {
        let results: [Result<String?, any Error>] = [.success(nil), .failure(AdapterLinkWriteError.linkLost)]
        for result in results {
            let harness = makeHarness()
            try await harness.driveToConfirming()
            try await harness.answerRespondingAndWaitForVINRead()
            harness.vinReader.responses.resumeOldest(with: result)
            try await harness.wait("検知通知") { harness.notifications.presentedVehicleDetectedVINs.count == 1 }
            XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [nil])
            let vehicle = AdapterLinkDetectedVehicle(adapterProbeEvidence: F.evidence, vin: nil)
            XCTAssertEqual(harness.useCase.state, .vehicleDetected(vehicle, phase: .awaitingRecordingStart))
        }
    }

    /// 初期化が失敗したら待機へ戻り、確認・検知・通知にはならず、リンクも止めません。
    ///
    /// 責務: 初期化失敗後の待機・確認なし・通知なし・停止なしを確認します。
    func testInitializationFailureReturnsToStandby() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.initialization.responses.resumeOldest(with: .failure(AdapterLinkWriteError.linkLost))
        try await harness.wait("待機へ戻る") { harness.useCase.state == .standby }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.vehicleResponse.timeouts, [])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
        XCTAssertEqual(harness.link.stopCount, 0)
    }

    /// 初期化失敗の後、アプリ前面復帰で初期化を再試行します。
    ///
    /// 責務: 前面復帰で初期化の呼び出しが2回目になり初期化中になることを確認します。
    func testInitializationIsRetriedOnForeground() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.initialization.responses.resumeOldest(with: .failure(AdapterLinkWriteError.linkLost))
        try await harness.wait("待機へ戻る") { harness.useCase.state == .standby }
        harness.clock.now = F.date(120)
        harness.useCase.appDidBecomeActive()
        try await harness.wait("初期化の再試行") { harness.initialization.responses.callCount == 2 }
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: F.date(120)))
    }

    /// 初期化失敗の後、次の再接続(再び `ready`)で初期化を再試行します。
    ///
    /// 責務: リンク断→`ready` で初期化の呼び出しが2回目になることを確認します。
    func testInitializationIsRetriedOnReconnect() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.initialization.responses.resumeOldest(with: .failure(AdapterLinkWriteError.linkLost))
        try await harness.wait("待機へ戻る") { harness.useCase.state == .standby }
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// 背面で時計が進まなくても、600回の確認の後は休止せず、5秒間隔で確認を続けます(S1-1)。
    ///
    /// 責務: 600回目の無応答で5秒の待機が要求され、その待機明けごとに確認が1回ずつ増え、状態が確認中のままであることを確認します
    /// (U3 受け入れ条件 4 を窓後継続へ改定)。
    func testFrozenClockInBackgroundContinuesAtExtendedIntervalAfterAttemptLimit() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await runNoResponseCyclesUntilExtendedWait(harness, eachTaking: 0)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, attemptLimit)
        XCTAssertEqual(harness.vehicleResponse.timeouts.first, .standard)
        XCTAssertEqual(harness.vehicleResponse.timeouts.dropFirst().filter { $0 == .adapterMaximum }.count, attemptLimit - 1)
        XCTAssertEqual(harness.clock.requestedDurations.last, .seconds(5))

        for round in 1...3 {
            let confirmations = harness.vehicleResponse.timeouts.count
            let sleeps = harness.clock.requestedDurations.count
            XCTAssertTrue(harness.clock.finishOldestSleep(advancingBy: 0))
            try await harness.wait("\(round)回目の窓後の確認") { harness.vehicleResponse.timeouts.count == confirmations + 1 }
            XCTAssertEqual(harness.vehicleResponse.timeouts.last, .adapterMaximum)
            XCTAssertTrue(harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse)))
            try await harness.wait("\(round)回目の窓後の待機") { harness.clock.requestedDurations.count == sleeps + 1 }
            XCTAssertEqual(harness.clock.requestedDurations.last, .seconds(5))
            XCTAssertTrue(harness.isConfirming(.probing))
        }
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
    }

    /// 確認窓は初期化完了ではなくリンク `ready` の時刻から10分で、窓を過ぎた再確認は5秒間隔になります(S1-1)。
    ///
    /// 責務: 初期化に100秒かかり1回の確認に3秒かかる場合、100〜598秒に送った167回の後(601秒に受け取り)は、休止せず
    /// 窓後の間隔(前回の確認から5秒)までの残り2秒の待機が要求され、その待機明けに168回目を送ることを確認します。
    /// 窓を初期化完了(100秒)から測ると、601秒はまだ窓の内なので待機は要求されません。
    func testWindowIsMeasuredFromLinkReadyTime() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.clock.now = F.date(100)
        try await harness.finishInitialization()
        try await runNoResponseCyclesUntilExtendedWait(harness, eachTaking: 3)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 167)
        XCTAssertEqual(harness.clock.requestedDurations.last, .seconds(2), "601秒に受け取り、最後の確認(598秒)から5秒後まで")
        XCTAssertEqual(harness.link.stopCount, 0)

        XCTAssertTrue(harness.clock.finishOldestSleep(advancingBy: 2))
        try await harness.wait("168回目の確認") { harness.vehicleResponse.timeouts.count == 168 }
        XCTAssertTrue(harness.isConfirming(.probing))
    }

    /// 窓後の待機中にアプリが前面へ戻っても、確認を重複させず、待機明けに確認を続けます。
    ///
    /// 責務: 前面復帰で確認の呼び出しが増えず確認中のままで、待機明けに確認が1回増えることを確認します(窓切れの取り直しは窓だけ)。
    func testForegroundDuringExtendedWaitDoesNotDuplicateConfirmation() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await runNoResponseCyclesUntilExtendedWait(harness, eachTaking: 0)
        harness.clock.now = F.date(5_000)
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, attemptLimit)
        XCTAssertTrue(harness.isConfirming(.probing))

        XCTAssertTrue(harness.clock.finishOldestSleep(advancingBy: 0))
        try await harness.wait("待機明けの確認") { harness.vehicleResponse.timeouts.count == attemptLimit + 1 }
        XCTAssertEqual(harness.vehicleResponse.timeouts.last, .adapterMaximum)
        XCTAssertTrue(harness.isConfirming(.probing))
    }

    /// 前面にいる間は、時計が進まず回数の上限(600回)に達しても休止せず、窓と回数を取り直して確認を続けます。
    ///
    /// 責務: 前面で上限を10回超える無応答を返しても `.paused` にならず、確認が送られ続けることを確認します(U8 R6)。
    func testFrozenClockInForegroundKeepsConfirmingBeyondAttemptLimit() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.useCase.appDidBecomeActive()
        let cycles = attemptLimit + 10

        for cycle in 1...cycles {
            guard try await answerNoResponseAndWaitForNextConfirmation(harness, cycle: cycle) else { return }
        }

        XCTAssertEqual(harness.vehicleResponse.timeouts.count, cycles + 1)
        XCTAssertTrue(harness.isConfirming(.probing))
    }

    /// 時計を進めずに無応答を返し、次の確認が送られるまで進めます(最短間隔の待ちが要求されたら時計を進めずに明けさせます)。
    ///
    /// 責務: 1周分を進め、休止した・保留が無い場合は失敗させて `false` を返します(呼び出し側は繰り返しを打ち切ります)。
    /// 待ちが上限内に成り立たなければ `harness.wait` が throw します。
    /// - Parameters:
    ///   - harness: 車両確認が1件保留されている手段。
    ///   - cycle: 何周目か(失敗時の表示用)。
    /// - Returns: 次の確認が送られれば `true`。
    private func answerNoResponseAndWaitForNextConfirmation(
        _ harness: AdapterLinkSupervisionHarness, cycle: Int, file: StaticString = #filePath, line: UInt = #line
    ) async throws -> Bool {
        let confirmations = harness.vehicleResponse.timeouts.count
        let sleeps = harness.clock.requestedDurations.count
        guard harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse), file: file, line: line) else { return false }
        try await harness.wait("\(cycle)周目: 次の確認か待機か休止", file: file, line: line) {
            harness.vehicleResponse.timeouts.count > confirmations || harness.clock.requestedDurations.count > sleeps
                || harness.isConfirming(.paused)
        }
        if harness.vehicleResponse.timeouts.count == confirmations, !harness.isConfirming(.paused) {
            guard harness.clock.finishOldestSleep(advancingBy: 0, file: file, line: line) else { return false }
            try await harness.wait("\(cycle)周目: 待ち明けの確認か休止", file: file, line: line) {
                harness.vehicleResponse.timeouts.count > confirmations || harness.isConfirming(.paused)
            }
        }
        guard !harness.isConfirming(.paused) else {
            XCTFail("前面にいるのに\(cycle)周目(確認 \(confirmations) 回)で休止した", file: file, line: line)
            return false
        }
        return true
    }

    /// 窓後の待機中に再接続(リンク断→`ready`)したら、待機を取り消して初期化からやり直します。
    ///
    /// 責務: 再接続で初期化の呼び出しが2回目になり、窓後の確認が追加されないことを確認します。
    func testReconnectDuringExtendedWaitRestartsFromInitialization() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await runNoResponseCyclesUntilExtendedWait(harness, eachTaking: 0)
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertEqual(harness.useCase.state, .standby)
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, attemptLimit)
    }

    /// 窓の内の低頻度確認中のアプリ前面復帰では、確認を二重に始めません。
    ///
    /// 責務: 1回目・2回目の確認の保留中の前面復帰で確認の呼び出しが増えないことを確認します(U3 受け入れ条件 5)。
    func testForegroundWhileProbingDoesNotDuplicateConfirmation() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 1)
        harness.clock.now = harness.clock.now.addingTimeInterval(30)
        harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
        try await harness.wait("2回目の確認") { harness.vehicleResponse.timeouts.count == 2 }
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 2)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
    }
}
