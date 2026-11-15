import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` で、リンク断・再接続の後に届いた古い非同期結果が状態を動かさないことを検証します。
@MainActor
final class AdapterLinkSupervisionUseCaseStaleResultTests: XCTestCase {
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

    /// 責務: 自動記録設定を指定して手段を組み立て、終了処理の対象に加えます。
    private func makeHarness(isAutomaticRecordingEnabled: Bool = false) -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness(isAutomaticRecordingEnabled: isAutomaticRecordingEnabled)
        harnesses.append(harness)
        return harness
    }

    /// リンク断の後に届いた初期化成功では確認を始めません。
    ///
    /// 責務: 初期化中にリンクが切れて待機へ戻り、古い初期化結果で状態が動かないことを確認します。
    func testInitializationResultAfterLinkLossIsIgnored() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertEqual(harness.useCase.state, .standby)

        harness.initialization.responses.resumeOldest(with: .success(F.evidence))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.vehicleResponse.timeouts, [])
    }

    /// 再接続後に届いた前回の初期化成功は、今回の初期化の結果として使いません。
    ///
    /// 責務: 古い結果では初期化中のまま、今回の結果の判定結果で確認中になることを確認します。
    func testPreviousInitializationResultAfterReconnectIsIgnored() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.pendingCount, 2)

        harness.initialization.responses.resumeOldest(with: .success(F.evidence))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))
        XCTAssertEqual(harness.vehicleResponse.timeouts, [])

        try await harness.finishInitialization(with: F.otherEvidence)
        guard case let .confirmingVehicle(confirmation) = harness.useCase.state else {
            return XCTFail("確認中にならない: \(harness.useCase.state)")
        }
        XCTAssertEqual(confirmation.adapterProbeEvidence, F.otherEvidence)
        XCTAssertEqual(harness.vehicleResponse.timeouts, [.standard])
    }

    /// リンク断の後に届いた初期化失敗でも状態を動かしません。
    ///
    /// 責務: 再接続後の初期化中に古い失敗が届いても、待機へ巻き戻さないことを確認します。
    func testPreviousInitializationFailureAfterReconnectIsIgnored() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await harness.makeLinkReady()

        harness.initialization.responses.resumeOldest(with: .failure(AdapterLinkWriteError.linkLost))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))
    }

    /// リンク断の後に届いた応答ありでは検知・VIN読取・通知をしません。
    ///
    /// 責務: 車両確認中にリンクが切れた後の古い確認結果が無視されることを確認します。
    func testConfirmationResultAfterLinkLossIsIgnored() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertEqual(harness.useCase.state, .standby)

        harness.vehicleResponse.responses.resumeOldest(with: .success(.responding))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.vinReader.responses.callCount, 0)
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
    }

    /// 再接続後の確認中に届いた前回の応答ありでは検知しません。
    ///
    /// 責務: 前回の確認結果が今回の確認窓で検知として扱われないことを確認します。
    func testPreviousConfirmationResultAfterReconnectIsIgnored() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await harness.makeLinkReady()
        try await harness.finishInitialization()

        harness.vehicleResponse.responses.resumeOldest(with: .success(.responding))
        try await BLEBoundedWaiter.settle()
        XCTAssertTrue(harness.isConfirming(.probing))
        XCTAssertEqual(harness.vinReader.responses.callCount, 0)
    }

    /// リンク断の後に再確認の待機が終わっても、確認を要求しません。
    ///
    /// 責務: 古い待機の完了で確認の呼び出しが増えず待機のままであることを確認します。
    func testIntervalAfterLinkLossIsIgnored() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await harness.answerNoResponseAndWaitForSleep()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))

        harness.clock.finishOldestSleep(advancingBy: 30)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 1)
        XCTAssertEqual(harness.useCase.state, .standby)
    }

    /// リンク断の後に届いたVINでは、通知も自動記録もしません。
    ///
    /// 責務: 自動記録オンでも、VIN読取中にリンクが切れた後の古い結果で記録開始要求・通知が出ないことを確認します。
    func testVINResultAfterLinkLossIsIgnored() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await harness.driveToConfirming()
        try await harness.answerRespondingAndWaitForVINRead()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))

        harness.vinReader.responses.resumeOldest(with: .success(F.vin))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.recordingControl.startRequests, [])
        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
    }
}
