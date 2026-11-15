import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` の初期化・車両確認・確認窓・休止と再開・検知通知を、fake の時計で検証します。
@MainActor
final class AdapterLinkSupervisionUseCaseVehicleConfirmationTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

    /// 休止まで回す無応答サイクルの上限です。仕様の20回を十分に超える値にし、休止しない不具合を失敗にします。
    private let maximumCycles = 30

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

    /// 無応答→待機終了を、休止するか上限回数に達するまで繰り返します。
    ///
    /// 責務: 保留中の確認へ無応答を返し、待機を指定秒数進めて終わらせる手順を、上限付きで繰り返します。上限内に休止しなければ失敗させます。
    /// - Parameters:
    ///   - harness: 車両確認が1件保留されている手段。
    ///   - seconds: 1回の待機で進める秒数。
    private func runNoResponseCyclesUntilPaused(
        _ harness: AdapterLinkSupervisionHarness, advancingBy seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        for _ in 0..<maximumCycles {
            let sleeps = harness.clock.requestedDurations.count
            let confirmations = harness.vehicleResponse.timeouts.count
            harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse), file: file, line: line)
            try await harness.wait("待機か休止", file: file, line: line) {
                harness.clock.requestedDurations.count > sleeps || harness.isConfirming(.paused)
            }
            if harness.isConfirming(.paused) { return }
            harness.clock.finishOldestSleep(advancingBy: seconds, file: file, line: line)
            try await harness.wait("再確認か休止", file: file, line: line) {
                harness.vehicleResponse.timeouts.count > confirmations || harness.isConfirming(.paused)
            }
            if harness.isConfirming(.paused) { return }
        }
        XCTFail("\(maximumCycles)回の無応答で休止しなかった", file: file, line: line)
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

    /// ECU無応答では通知を出さず、リンクを止めずに30秒の待機を予約します。
    ///
    /// 責務: 通知0件・リンク停止0回・待機時間30秒・確認中のままを確認します。
    func testNoResponseDoesNotNotifyAndKeepsLink() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await harness.answerNoResponseAndWaitForSleep()
        XCTAssertEqual(harness.clock.requestedDurations, [.seconds(30)])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.link.stopCount, 0)
        XCTAssertTrue(harness.isConfirming(.probing))
    }

    /// 待機が終わると、アダプター最大タイムアウトで再確認します。
    ///
    /// 責務: 2回目以降の確認へ `.adapterMaximum` が渡ることを確認します。
    func testRecheckAfterIntervalUsesAdapterMaximumTimeout() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await harness.answerNoResponseAndWaitForSleep()
        harness.clock.finishOldestSleep(advancingBy: 30)
        try await harness.wait("2回目の確認") { harness.vehicleResponse.timeouts.count == 2 }
        XCTAssertEqual(harness.vehicleResponse.timeouts, [.standard, .adapterMaximum])
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

    /// 時計が進まなくても、1窓の確認は20回(通常1回+最大19回)で止まり休止します。
    ///
    /// 責務: 確認回数とタイムアウト種別の内訳、休止後に待機も確認も追加されないことを確認します。
    func testFrozenClockStopsAfterTwentyConfirmations() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await runNoResponseCyclesUntilPaused(harness, advancingBy: 0)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, F.maximumAttempts)
        XCTAssertEqual(harness.vehicleResponse.timeouts.first, .standard)
        XCTAssertEqual(harness.vehicleResponse.timeouts.dropFirst().filter { $0 == .adapterMaximum }.count, F.maximumAttempts - 1)
        XCTAssertEqual(harness.clock.sleeps.pendingCount, 0)
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
    }

    /// 確認窓は初期化完了ではなくリンク `ready` の時刻から10分で、窓を過ぎた再確認は行いません。
    ///
    /// 責務: 初期化に100秒かかった場合、100〜580秒の17回で確認が止まり休止することを確認します。
    func testWindowIsMeasuredFromLinkReadyTime() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.clock.now = F.date(100)
        try await harness.finishInitialization()
        try await runNoResponseCyclesUntilPaused(harness, advancingBy: 30)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 17)
        XCTAssertEqual(harness.link.stopCount, 0)
    }

    /// 休止中にアプリ前面復帰したら、10分の窓を取り直して確認を再開し、新しい窓でも20回まで確認します。
    ///
    /// 責務: 再開の確認が最大タイムアウトであること、再開後にも回数上限が新しく数えられることを確認します。
    func testForegroundResumesPausedConfirmationWithNewWindow() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await runNoResponseCyclesUntilPaused(harness, advancingBy: 0)
        harness.clock.now = F.date(5_000)
        harness.useCase.appDidBecomeActive()
        try await harness.wait("再開の確認") { harness.vehicleResponse.timeouts.count == F.maximumAttempts + 1 }
        XCTAssertEqual(harness.vehicleResponse.timeouts.last, .adapterMaximum)
        XCTAssertTrue(harness.isConfirming(.probing))

        try await runNoResponseCyclesUntilPaused(harness, advancingBy: 0)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, F.maximumAttempts * 2)
    }

    /// 休止中に再接続(リンク断→`ready`)したら、初期化からやり直します。
    ///
    /// 責務: 休止からの再接続で初期化の呼び出しが2回目になることを確認します。
    func testReconnectWhilePausedRestartsFromInitialization() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await runNoResponseCyclesUntilPaused(harness, advancingBy: 0)
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertEqual(harness.useCase.state, .standby)
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// 低頻度確認中のアプリ前面復帰では、確認を二重に始めません。
    ///
    /// 責務: 確認の保留中・待機中の前面復帰で確認の呼び出しが増えないことを確認します。
    func testForegroundWhileProbingDoesNotDuplicateConfirmation() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.useCase.appDidBecomeActive()
        try await harness.answerNoResponseAndWaitForSleep()
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 1)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
    }
}
