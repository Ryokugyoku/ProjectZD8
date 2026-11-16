import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` が「記録開始の意思」を期限ちょうどまで使い、1回で消し、処理できない時と期限切れに
/// 理由つきの「記録を開始できませんでした」を出すことを検証します。
///
/// 仕様: U4 受け入れ条件 5〜8・10。時間は fake の時計の `now` と待機の完了で表します。
@MainActor
final class AdapterLinkSupervisionUseCaseRecordingIntentOutcomeTests: XCTestCase {
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

    /// 自動記録オフの手段を組み立て、終了処理の対象に加えます。
    ///
    /// 責務: 既定アダプター設定を指定した手段を返します。
    /// - Parameter defaultAdapter: 保存済みの既定アダプター設定。
    /// - Returns: 手段。
    private func makeHarness(defaultAdapter: DefaultAdapterPreference? = F.blePreference) -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness(defaultAdapter: defaultAdapter, isAutomaticRecordingEnabled: false)
        harnesses.append(harness)
        return harness
    }

    /// リンク `ready` から VIN 読取の完了まで、車両の検知を進めます(時計は進めません)。
    ///
    /// 責務: 初期化・ECU の応答・VIN 読取を順に完了させ、記録開始要求か検知通知が増えるまで待ちます。
    /// - Parameter harness: 監視を開始済みの手段。
    private func completeDetection(_ harness: AdapterLinkSupervisionHarness, file: StaticString = #filePath, line: UInt = #line) async throws {
        let starts = harness.recordingControl.startRequests.count
        let detections = harness.notifications.presentedVehicleDetectedVINs.count
        try await harness.makeLinkReady(file: file, line: line)
        try await harness.finishInitialization(file: file, line: line)
        try await harness.answerRespondingAndWaitForVINRead(file: file, line: line)
        harness.vinReader.responses.resumeOldest(with: .success(F.vin), file: file, line: line)
        try await harness.wait("検知の後の記録開始か検知通知", file: file, line: line) {
            harness.recordingControl.startRequests.count > starts || harness.notifications.presentedVehicleDetectedVINs.count > detections
        }
    }

    /// 選択を意思として保持させ、期限の満了の待ちが始まるまで待ちます。
    ///
    /// 責務: `recordingStartSelected()` を呼び、120.001 秒の待機が要求されるまで上限付きで待ちます。
    /// - Parameter harness: 監視を開始済みの手段。
    private func selectAndWaitForExpirySleep(_ harness: AdapterLinkSupervisionHarness, file: StaticString = #filePath, line: UInt = #line) async throws {
        harness.useCase.recordingStartSelected()
        try await harness.wait("期限の待ち", file: file, line: line) {
            harness.clock.requestedDurations.contains(.milliseconds(120_001))
        }
    }

    /// サインインしていない時の[記録開始]は捨て、「サインインが必要」を知らせます。
    ///
    /// 責務: 未サインインで監視を開始した後の選択で、理由 `.signInRequired` が1件出ることを確認します(受け入れ条件 7)。
    func testSelectionWhileSignedOutNotifiesSignInRequired() {
        let harness = makeHarness()
        harness.useCase.start()

        harness.useCase.recordingStartSelected()

        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [.signInRequired])
        XCTAssertEqual(harness.recordingControl.startRequests, [])
    }

    /// 既定のアダプターが無い、またはBLE以外の時の[記録開始]は捨て、「アダプターが未設定」を知らせます。
    ///
    /// 責務: 既定なし・Classic の両方で理由 `.adapterNotConfigured` が1件出ることを確認します(受け入れ条件 7)。
    func testSelectionWithoutBLEDefaultAdapterNotifiesAdapterNotConfigured() {
        for preference in [nil, F.classicPreference] {
            let harness = makeHarness(defaultAdapter: preference)
            harness.startSignedIn()

            harness.useCase.recordingStartSelected()

            XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [.adapterNotConfigured], "\(String(describing: preference))")
        }
    }

    /// 監視が動いていない時の[記録開始]は捨て、「車両を検知できなかった」を知らせます。
    ///
    /// 責務: 監視の開始前の選択で理由 `.vehicleNotDetected` が1件出ることを確認します(受け入れ条件 7)。
    func testSelectionBeforeSupervisionStartNotifiesVehicleNotDetected() {
        let harness = makeHarness()

        harness.useCase.recordingStartSelected()

        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [.vehicleNotDetected])
    }

    /// 期限ちょうど(2分)に検知が完了すれば、意思は有効で、検知通知を出さずに記録を始めます。
    ///
    /// 責務: 選択から120秒後の検知完了で記録開始要求1件・検知通知0件・失敗通知0件であることを確認します(受け入れ条件 5・10 の境界)。
    func testDetectionExactlyAtLifetimeStartsRecording() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.recordingStartSelected()
        harness.clock.now = F.date(120)

        try await completeDetection(harness)

        XCTAssertEqual(harness.recordingControl.startRequests, [F.expectedStartRequest(vin: F.vin)])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [])
    }

    /// 期限を過ぎた直後(期限の待ちが動く前)に検知が完了したら、意思は黙って消し、「記録を開始できませんでした」は出しません。
    ///
    /// 責務: 120.001秒後の検知完了で、検知通知1件・失敗通知0件・記録開始要求0件・`.vehicleDetected(.awaitingRecordingStart)` で、
    /// その後に期限の待ちが明けても失敗通知が出ず、検知通知を取り下げないことを確認します(U8 R2。U4 受け入れ条件 7 の改訂)。
    func testDetectionJustAfterLifetimeDropsIntentSilentlyAndKeepsDetection() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await selectAndWaitForExpirySleep(harness)
        harness.clock.now = F.date(120.001)

        try await completeDetection(harness)

        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [F.vin])
        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [], "検知が完了した時点で期限切れの意思は黙って消す")
        XCTAssertEqual(harness.recordingControl.startRequests, [])
        XCTAssertEqual(harness.useCase.state, .vehicleDetected(F.detectedVehicle, phase: .awaitingRecordingStart))

        let dismissals = harness.notifications.dismissCount
        guard harness.clock.finishOldestSleep(advancingBy: 0) else { return }
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [], "期限の待ちが明けても失敗通知を出さない")
        XCTAssertEqual(harness.notifications.dismissCount, dismissals, "検知通知を取り下げない")
        XCTAssertEqual(harness.useCase.state, .vehicleDetected(F.detectedVehicle, phase: .awaitingRecordingStart))
    }

    /// 検知が完了しないまま期限が切れたら、その時点で意思を捨てて「車両を検知できなかった」を知らせます。
    ///
    /// 責務: 期限の待ちを 120.001 秒進めて終えると失敗通知が1件出て、その後の検知では記録を始めず通常の検知通知になることを確認します(受け入れ条件 7)。
    func testExpiryWithoutDetectionNotifiesAndDropsIntent() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await selectAndWaitForExpirySleep(harness)
        XCTAssertEqual(harness.clock.sleeps.pendingCount, 1, "期限の待ちだけが保留されている")

        harness.clock.finishOldestSleep(advancingBy: 120.001)
        try await harness.wait("期限切れの通知") { !harness.notifications.presentedRecordingStartFailedReasons.isEmpty }
        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [.vehicleNotDetected])

        try await completeDetection(harness)
        XCTAssertEqual(harness.recordingControl.startRequests, [])
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [F.vin])
        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [.vehicleNotDetected], "期限切れの通知は1回だけ")
    }

    /// 意思は1回使ったら消え、次の検知では通常の検知通知になります。
    ///
    /// 責務: 意思で始めた記録が接続断で終わった後の再検知で、記録開始要求が増えず検知通知が1件出ることを確認します(受け入れ条件 6)。
    func testIntentIsConsumedByFirstDetection() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.useCase.recordingStartSelected()
        try await completeDetection(harness)
        XCTAssertEqual(harness.recordingControl.startRequests.count, 1)

        harness.useCase.recordingDidFinish(endReason: .connectionLost)
        try await harness.wait("再検知の初期化") { harness.initialization.responses.callCount == 2 }
        try await harness.finishInitialization()
        try await harness.answerRespondingAndWaitForVINRead()
        harness.vinReader.responses.resumeOldest(with: .success(F.vin))
        try await harness.wait("2回目の検知通知") { harness.notifications.presentedVehicleDetectedVINs.count == 1 }

        XCTAssertEqual(harness.recordingControl.startRequests.count, 1)
        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [])
    }

    /// VIN読取中に届いた[記録開始]も意思として保持し、読取の完了で検知通知を出さずに記録を始めます。
    ///
    /// 責務: 読取中の選択の後の読取完了で、記録開始要求1件・検知通知0件であることを確認します(受け入れ条件 5・6)。
    func testSelectionWhileReadingVINStartsRecordingOnCompletion() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        try await harness.answerRespondingAndWaitForVINRead()

        harness.useCase.recordingStartSelected()
        harness.vinReader.responses.resumeOldest(with: .success(F.vin))

        try await harness.wait("記録開始要求") { harness.recordingControl.startRequests.count == 1 }
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
        XCTAssertEqual(harness.useCase.state, .recording(F.detectedVehicle))
    }

    /// 意思を保持している間にサインアウトしたら、意思を捨てて「サインインが必要」を知らせます。
    ///
    /// 責務: 保持中のサインアウトで失敗通知 `[.signInRequired]` が出て、記録開始要求が出ないことを確認します(受け入れ条件 7)。
    func testSignOutWhileHoldingIntentNotifiesSignInRequired() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await selectAndWaitForExpirySleep(harness)

        harness.useCase.authenticationDidChange(isSignedIn: false)

        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [.signInRequired])
        XCTAssertEqual(harness.recordingControl.startRequests, [])
    }

    /// 意思を保持している間に既定のアダプターが削除されたら、意思を捨てて「アダプターが未設定」を知らせます。
    ///
    /// 責務: 保持中の既定アダプターの削除で失敗通知 `[.adapterNotConfigured]` が出ることを確認します(受け入れ条件 7)。
    func testDefaultAdapterRemovedWhileHoldingIntentNotifiesAdapterNotConfigured() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await selectAndWaitForExpirySleep(harness)

        harness.preferenceStore.preference = nil
        harness.useCase.defaultAdapterPreferenceDidChange()

        XCTAssertEqual(harness.notifications.presentedRecordingStartFailedReasons, [.adapterNotConfigured])
    }

    /// 監視の開始時の通知の取り下げは、サインインの有無によらず行います。
    ///
    /// 責務: 未サインインのまま `start()` しても取り下げが1回以上行われることを確認します(受け入れ条件 8)。
    func testSupervisionStartDismissesLeftoverNotificationEvenWhenSignedOut() {
        let harness = makeHarness()
        harness.useCase.start()
        XCTAssertGreaterThan(harness.notifications.dismissCount, 0)
    }
}
