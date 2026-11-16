import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` の自動記録・通知からの手動記録開始・記録終了・リンク断と前面復帰を検証します。
@MainActor
final class AdapterLinkSupervisionUseCaseRecordingTests: XCTestCase {
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

    /// 車両確認中から応答あり・VIN読取完了まで進めます。
    ///
    /// 責務: 検知の直前(VIN読取の保留)まで進め、指定のVINを返します。
    private func detect(_ harness: AdapterLinkSupervisionHarness, vin: String? = F.vin) async throws {
        try await harness.answerRespondingAndWaitForVINRead()
        harness.vinReader.responses.resumeOldest(with: .success(vin))
    }

    /// 自動記録オンなら、操作なしで記録開始を要求し「記録を開始しました」通知を出して記録中へ移ります。
    ///
    /// 責務: 記録開始要求1件(接続終端・VIN・判定結果)・記録開始通知1件・検知通知なしを確認します。
    func testAutomaticRecordingOnStartsRecordingWithoutAction() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await harness.driveToConfirming()
        try await detect(harness)
        try await harness.wait("記録開始要求") { harness.recordingControl.startRequests.count == 1 }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.recordingControl.startRequests, [F.expectedStartRequest(vin: F.vin)])
        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [F.vin])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
        XCTAssertEqual(harness.useCase.state, .recording(F.detectedVehicle))
    }

    /// 自動記録オフでは、検知しても記録は始まりません。
    ///
    /// 責務: 記録開始要求・記録開始通知が0件であることを確認します。
    func testAutomaticRecordingOffDoesNotStartRecording() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: false)
        try await harness.driveToAwaitingRecordingStart()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.recordingControl.startRequests, [])
        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
    }

    /// 自動記録設定は検知時点の値を読みます(開始後にオンへ変えれば、その検知から自動記録します)。
    ///
    /// 責務: 監視開始時はオフ、検知前にオンへ変えた場合に記録開始要求が出ることを確認します。
    func testAutomaticRecordingPreferenceIsReadAtDetection() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: false)
        try await harness.driveToConfirming()
        harness.automaticRecording.isEnabled = true
        try await detect(harness)
        try await harness.wait("記録開始要求") { harness.recordingControl.startRequests.count == 1 }
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
    }

    /// 自動記録設定を検知前にオフへ変えれば、その検知では自動記録しません。
    ///
    /// 責務: 監視開始時はオン、検知前にオフへ変えた場合に検知通知だけが出ることを確認します。
    func testAutomaticRecordingTurnedOffBeforeDetectionNotifiesInstead() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await harness.driveToConfirming()
        harness.automaticRecording.isEnabled = false
        try await detect(harness)
        try await harness.wait("検知通知") { harness.notifications.presentedVehicleDetectedVINs.count == 1 }
        XCTAssertEqual(harness.recordingControl.startRequests, [])
    }

    /// 通知の[記録開始]選択で、検知通知を取り下げ、接続終端・VIN・判定結果付きで記録開始を要求します。
    ///
    /// 責務: 通知ポートへ渡された受け口からの選択が記録中になり、記録開始通知は出さないことを確認します。
    func testRecordingStartSelectedFromNotificationStartsRecording() async throws {
        let harness = makeHarness()
        try await harness.driveToAwaitingRecordingStart()
        try await harness.wait("通知の準備") { harness.notifications.recordingStartSelected != nil }
        let dismissals = harness.notifications.dismissCount

        harness.notifications.recordingStartSelected?()

        XCTAssertEqual(harness.recordingControl.startRequests, [F.expectedStartRequest(vin: F.vin)])
        XCTAssertGreaterThan(harness.notifications.dismissCount, dismissals)
        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.useCase.state, .recording(F.detectedVehicle))
    }

    /// [記録開始]の重複選択でも記録開始は1回だけです。
    ///
    /// 責務: 記録中に届いた2回目の選択を無視することを確認します。
    func testRepeatedRecordingStartSelectedStartsOnce() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.useCase.recordingStartSelected()
        XCTAssertEqual(harness.recordingControl.startRequests.count, 1)
    }

    /// 検知済み以外(待機・初期化中・確認中・VIN読取中)で届いた[記録開始]は記録を始めません。
    ///
    /// 責務: 各段階で選択しても記録開始要求が0件のままであることを確認します。
    func testRecordingStartSelectedOutsideDetectedIsIgnored() async throws {
        let harness = makeHarness()
        harness.useCase.recordingStartSelected()
        harness.startSignedIn()
        harness.useCase.recordingStartSelected()
        try await harness.makeLinkReady()
        harness.useCase.recordingStartSelected()
        try await harness.finishInitialization()
        harness.useCase.recordingStartSelected()
        try await harness.answerRespondingAndWaitForVINRead()
        harness.useCase.recordingStartSelected()
        XCTAssertEqual(harness.recordingControl.startRequests, [])
    }

    /// 記録中に記録終了が通知されたら待機へ戻り、停止要求は出しません。
    ///
    /// 責務: 記録終了後の待機と停止要求0件を確認します。
    func testRecordingDidFinishReturnsToStandby() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.useCase.recordingDidFinish(endReason: nil)
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
    }

    /// 記録中に記録終了が通知されたら、終了を経て待機へ戻ります(記録終了の通知1回で待機まで進みます)。
    ///
    /// 責務: 通知された状態の並びが「記録中 → 終了 → 待機」で、停止要求が出ず、リンクも止めないことを確認します。
    func testRecordingDidFinishPassesThroughFinishingToStandby() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        let statesBefore = harness.observedStates.count

        harness.useCase.recordingDidFinish(endReason: nil)

        XCTAssertEqual(Array(harness.observedStates.dropFirst(statesBefore)), [.finishing, .standby])
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
        XCTAssertEqual(harness.link.stopCount, 0)
    }

    /// 記録中にリンクが切れても停止を要求せず記録中のままで、猶予切れの記録終了(接続断)の通知後に終了を経て待機へ戻ります。
    ///
    /// 責務: 停止要求0回・記録中のまま・リンクを止めないこと、接続断での記録終了で「終了 → 待機」になり抑止しないことを確認します(U2 受け入れ条件 1・3)。
    func testLinkLossWhileRecordingKeepsRecordingUntilRecordingFinishes() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        let recording = harness.useCase.state
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
        XCTAssertEqual(harness.useCase.state, recording)
        XCTAssertEqual(harness.link.stopCount, 0)
        let statesBefore = harness.observedStates.count

        harness.useCase.recordingDidFinish(endReason: .connectionLost)

        XCTAssertEqual(Array(harness.observedStates.dropFirst(statesBefore)), [.finishing, .standby])
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
    }

    /// 記録中にリンクが切れて `ready` へ戻っても、初期化・車両確認をやり直さず記録中のままです。
    ///
    /// 責務: 再接続の後も初期化・確認の呼び出しが増えず、停止要求も記録開始要求も増えないことを確認します(U2 受け入れ条件 1・7)。
    func testLinkReturnsReadyWhileRecordingDoesNotReinitialize() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        let recording = harness.useCase.state
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        harness.link.emit(.connecting)
        harness.link.emit(.ready)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.useCase.state, recording)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 1)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
        XCTAssertEqual(harness.recordingControl.startRequests.count, 1)
    }

    /// リンク断のあいだにユーザーが切断した場合、抑止せず待機へ戻り、次の再接続で初期化からやり直します。
    ///
    /// 責務: 停止要求0回・待機・再接続での初期化2回目を確認します(U2 受け入れ条件 8)。
    func testUserStopDuringLinkLossReturnsToStandby() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))

        harness.useCase.recordingDidFinish(endReason: .userDisconnected)

        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// リンク断の後にリンクが `ready` へ戻ってからユーザーが切断した場合は、従来どおり抑止状態へ移ります。
    ///
    /// 責務: 同じ接続が使える時のユーザー切断が `heldAfterUserStop` になり、停止要求が出ていないことを確認します(U2 受け入れ条件 8)。
    func testUserStopAfterLinkReturnedHoldsSameConnection() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        harness.link.emit(.connecting)
        harness.link.emit(.ready)

        harness.useCase.recordingDidFinish(endReason: .userDisconnected)

        XCTAssertEqual(harness.useCase.state, F.watching(endsAt: harness.clock.now.addingTimeInterval(F.heldWatchSeconds)))
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
    }

    /// 検知済みでリンクが切れたら、検知通知を取り下げて待機へ戻り、後の[記録開始]を無視します。
    ///
    /// 責務: 取り下げ・待機・記録開始要求0件を確認します。
    func testLinkLossWhileDetectedDismissesNotification() async throws {
        let harness = makeHarness()
        try await harness.driveToAwaitingRecordingStart()
        let dismissals = harness.notifications.dismissCount
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertGreaterThan(harness.notifications.dismissCount, dismissals)
        XCTAssertEqual(harness.useCase.state, .standby)
        harness.useCase.recordingStartSelected()
        XCTAssertEqual(harness.recordingControl.startRequests, [])
    }

    /// 記録がユーザー切断以外の理由で終わり、リンクが `ready` のままなら、前面復帰を待たずに終了時刻から初期化をやり直します。
    ///
    /// 責務: 接続断・車両無応答の終了で、初期化の呼び出しが2回目になり `.initializing(linkReadyAt: 終了時刻)` になることを確認します(U3 受け入れ条件 13)。
    func testAfterNonUserFinishWithReadyLinkRestartsDetection() async throws {
        for reason in [ConnectionSessionEndReason.connectionLost, .vehicleNoResponse] {
            let harness = makeHarness()
            try await harness.driveToRecording()
            let finishedAt = F.date(900)
            harness.clock.now = finishedAt

            harness.useCase.recordingDidFinish(endReason: reason)

            try await harness.wait("初期化のやり直し \(reason)") { harness.initialization.responses.callCount == 2 }
            XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: finishedAt), "\(reason)")
        }
    }

    /// 記録がユーザー切断以外の理由で終わった時にリンクが `ready` でなければ、待機に留まり、再接続で初期化を始めます。
    ///
    /// 責務: リンク断中の接続断の終了で待機・初期化なしのまま、再接続で初期化が2回目になることを確認します(U3 受け入れ条件 13)。
    func testAfterNonUserFinishWithoutReadyLinkWaitsForReconnect() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        harness.useCase.recordingDidFinish(endReason: .connectionLost)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)

        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// 記録終了後、次の再接続(リンク断→`ready`)で初期化からやり直します。
    ///
    /// 責務: 再接続で初期化の呼び出しが2回目になることを確認します。
    func testAfterFinishingReconnectRestartsFromInitialization() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.useCase.recordingDidFinish(endReason: nil)
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// 検知済み・記録中・終了中のアプリ前面復帰では状態を変えません。
    ///
    /// 責務: 各状態(記録中はリンク断のあいだも含む)で前面復帰しても状態・初期化・確認・記録要求が変わらないことを確認します。
    /// 終了中へは手動接続の開始で移します(リンク断では記録中のままのため。U2 受け入れ条件 1)。
    func testForegroundDoesNotChangeDetectedRecordingOrFinishing() async throws {
        let harness = makeHarness()
        try await harness.driveToAwaitingRecordingStart()
        let detected = harness.useCase.state
        harness.useCase.appDidBecomeActive()
        XCTAssertEqual(harness.useCase.state, detected)

        harness.useCase.recordingStartSelected()
        let recording = harness.useCase.state
        harness.useCase.appDidBecomeActive()
        XCTAssertEqual(harness.useCase.state, recording)

        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        harness.useCase.appDidBecomeActive()
        XCTAssertEqual(harness.useCase.state, recording, "リンク断の記録中")

        harness.useCase.externalAdapterUseDidBegin()
        harness.useCase.appDidBecomeActive()
        XCTAssertEqual(harness.useCase.state, .finishing)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 1)
        XCTAssertEqual(harness.recordingControl.startRequests.count, 1)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 1)
    }
}
