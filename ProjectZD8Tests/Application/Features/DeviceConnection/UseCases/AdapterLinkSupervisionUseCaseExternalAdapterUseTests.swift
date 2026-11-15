import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` の入力 `externalAdapterUseDidBegin()` / `externalAdapterUseDidEnd()` による
/// 監視の抑止と解除を、fake のポートを通して検証します。
@MainActor
final class AdapterLinkSupervisionUseCaseExternalAdapterUseTests: XCTestCase {
    /// 共通の fixture です。
    private typealias F = AdapterLinkSupervisionFixtures

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

    /// 初期化中に手動使用が始まったら待機へ戻り、遅れて届いた初期化成功では車両確認を始めません。
    ///
    /// 責務: 取り消し後の古い初期化結果が状態を動かさず、リンクを止めないことを確認します。
    func testBeginDuringInitializationCancelsAndIgnoresLateResult() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()

        harness.useCase.externalAdapterUseDidBegin()
        XCTAssertEqual(harness.useCase.state, .standby)
        harness.initialization.responses.resumeOldest(with: .success(F.evidence))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.vehicleResponse.timeouts, [])
        XCTAssertEqual(harness.link.stopCount, 0)
    }

    /// 車両確認中に手動使用が始まったら待機へ戻り、遅れて届いた「応答あり」でVINを読みに行きません。
    ///
    /// 責務: 取り消し後の古い確認結果で VIN 読取・検知通知が起きないことを確認します。
    func testBeginDuringConfirmationCancelsAndIgnoresLateResult() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()

        harness.useCase.externalAdapterUseDidBegin()
        XCTAssertEqual(harness.useCase.state, .standby)
        harness.vehicleResponse.responses.resumeOldest(with: .success(.responding))
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.vinReader.responses.callCount, 0)
        XCTAssertTrue(harness.notifications.presentedVehicleDetectedVINs.isEmpty)
        XCTAssertEqual(harness.link.stopCount, 0)
    }

    /// 再確認の待機中に手動使用が始まったら、待機が明けても車両確認を再開しません。
    ///
    /// 責務: 休止中の取り消し後、遅れて終わった待機で確認が始まらないことを確認します。
    func testBeginDuringPausedConfirmationIgnoresLateInterval() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await harness.answerNoResponseAndWaitForSleep()
        let confirmations = harness.vehicleResponse.timeouts.count

        harness.useCase.externalAdapterUseDidBegin()
        harness.clock.finishOldestSleep(advancingBy: F.intervalSeconds)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, confirmations)
    }

    /// 検知済み(記録開始待ち)で手動使用が始まったら、検知通知を取り下げて待機へ戻り、[記録開始]を受け付けません。
    ///
    /// 責務: 通知の取り下げが起き、その後の記録開始選択で記録開始要求が出ないことを確認します。
    func testBeginWhileAwaitingRecordingStartDismissesNotification() async throws {
        let harness = makeHarness()
        try await harness.driveToAwaitingRecordingStart()
        let dismisses = harness.notifications.dismissCount

        harness.useCase.externalAdapterUseDidBegin()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.notifications.dismissCount, dismisses + 1)
        harness.useCase.recordingStartSelected()

        XCTAssertTrue(harness.recordingControl.startRequests.isEmpty)
        XCTAssertEqual(harness.link.stopCount, 0)
    }

    /// 記録中に手動使用が始まったら記録の停止を要求して終了へ進み、記録終了の通知で待機へ戻ります。
    ///
    /// 責務: 停止要求が1回出て、リンクを止めず、`recordingDidFinish()` で待機へ戻ることを確認します。
    func testBeginWhileRecordingRequestsStopAndFinishes() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()

        harness.useCase.externalAdapterUseDidBegin()
        XCTAssertEqual(harness.useCase.state, .finishing)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 1)
        harness.useCase.recordingDidFinish()

        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.link.stopCount, 0)
    }

    /// 抑止中はリンクが `ready` になっても、アプリが前面へ戻っても、初期化を始めず通知も出しません。
    ///
    /// 責務: 抑止中の再接続と前面復帰で初期化の呼び出しが起きないことを確認します。
    func testSuppressedLinkReadyAndForegroundDoNotInitialize() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.externalAdapterUseDidBegin()

        harness.link.emit(.connecting)
        harness.link.emit(.ready)
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.initialization.responses.callCount, 0)
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertTrue(harness.notifications.presentedVehicleDetectedVINs.isEmpty)
        XCTAssertTrue(harness.notifications.presentedRecordingStartedVINs.isEmpty)
    }

    /// 手動使用が終わってもすぐには再確認せず、アプリの前面復帰で初期化からやり直します。
    ///
    /// 責務: 解除直後は初期化が呼ばれず、前面復帰で1回呼ばれることを確認します。
    func testEndThenForegroundRestartsFromInitialization() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.externalAdapterUseDidBegin()
        harness.link.emit(.connecting)
        harness.link.emit(.ready)

        harness.useCase.externalAdapterUseDidEnd()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 0)
        XCTAssertEqual(harness.useCase.state, .standby)

        harness.useCase.appDidBecomeActive()
        try await harness.wait("前面復帰での初期化") { harness.initialization.responses.callCount == 1 }
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))
    }

    /// 手動使用が終わった後の再接続(再び `ready`)で初期化からやり直します。
    ///
    /// 責務: 解除後にリンクが切れて再接続した時に初期化が1回呼ばれることを確認します。
    func testEndThenReconnectRestartsFromInitialization() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.externalAdapterUseDidBegin()
        harness.link.emit(.connecting)
        harness.link.emit(.ready)
        harness.useCase.externalAdapterUseDidEnd()

        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await harness.makeLinkReady()

        XCTAssertEqual(harness.initialization.responses.callCount, 1)
    }

    /// 抑止中でもサインアウトと `stop()` はリンクを停止します。
    ///
    /// 責務: 抑止中の稼働条件の喪失が従来どおりリンク停止になることを確認します。
    func testSignOutAndStopStillStopLinkWhileSuppressed() async throws {
        let signOut = makeHarness()
        signOut.startSignedIn()
        signOut.useCase.externalAdapterUseDidBegin()
        signOut.useCase.authenticationDidChange(isSignedIn: false)
        XCTAssertEqual(signOut.link.stopCount, 1)

        let stop = makeHarness()
        stop.startSignedIn()
        stop.useCase.externalAdapterUseDidBegin()
        stop.useCase.stop()
        XCTAssertEqual(stop.link.stopCount, 1)
    }

    /// 抑止中でもリンク断は従来どおり扱われ、記録中なら停止を要求します。
    ///
    /// 責務: 抑止前の記録が手動使用開始で終了中になった後、リンク断で状態が壊れず終了中のままであることを確認します。
    func testLinkLossWhileSuppressedKeepsFinishing() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.useCase.externalAdapterUseDidBegin()

        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))

        XCTAssertEqual(harness.useCase.state, .finishing)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 1)
    }

    /// 手動使用を一度も伝えなければ、リンクの `ready` で従来どおり初期化を始めます。
    ///
    /// 責務: 抑止の既定値が「抑止なし」であることを利用者側の入力で確認します。
    func testWithoutExternalUseLinkReadyInitializes() async throws {
        let harness = makeHarness()
        harness.startSignedIn()

        try await harness.makeLinkReady()

        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))
    }
}
