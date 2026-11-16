import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase.recordingDidStart()`(記録開始の確定)の後にだけ「記録を開始しました」を出すことを検証します。
///
/// 仕様: U4 受け入れ条件 1〜4。確定の前・辞退・失敗・古い確定・手動開始・意思での開始では出しません。
@MainActor
final class AdapterLinkSupervisionUseCaseRecordingStartConfirmationTests: XCTestCase {
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
    private func makeHarness(isAutomaticRecordingEnabled: Bool) -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness(isAutomaticRecordingEnabled: isAutomaticRecordingEnabled)
        harnesses.append(harness)
        return harness
    }

    /// 自動記録オンで車両を検知し、記録開始要求が出るまで進めます。
    ///
    /// 責務: 確認中から応答あり・VIN読取完了を経て、記録開始要求1件・記録中になるまで待ちます。
    /// - Parameters:
    ///   - harness: 自動記録オンの手段。
    ///   - vin: VIN読取で返す値。
    private func driveToAutomaticRecording(
        _ harness: AdapterLinkSupervisionHarness, vin: String? = F.vin, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        try await harness.driveToConfirming(file: file, line: line)
        try await harness.answerRespondingAndWaitForVINRead(file: file, line: line)
        harness.vinReader.responses.resumeOldest(with: .success(vin), file: file, line: line)
        try await harness.wait("記録開始要求", file: file, line: line) { harness.recordingControl.startRequests.count == 1 }
        XCTAssertTrue(harness.isRecording, file: file, line: line)
    }

    /// 自動記録の開始が確定したら、検知した車両のVINで「記録を開始しました」を1回出し、記録中のままです。
    ///
    /// 責務: 確定前0件・確定後 `[VIN]`・状態が記録中のままであることを確認します(受け入れ条件 1)。
    func testConfirmationAfterAutomaticStartAnnouncesOnce() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await driveToAutomaticRecording(harness)
        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])

        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [F.vin])
        XCTAssertEqual(harness.useCase.state, .recording(F.detectedVehicle))
    }

    /// VINを読めなかった自動記録の確定では、VINなしの「記録を開始しました」を出します。
    ///
    /// 責務: VIN読取が `nil` の記録の確定で、開始通知が `[nil]` になることを確認します(受け入れ条件 1)。
    func testConfirmationWithoutVINAnnouncesWithoutVIN() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await driveToAutomaticRecording(harness, vin: nil)

        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [nil])
    }

    /// 同じ記録への2回目の確定では、「記録を開始しました」を重ねて出しません。
    ///
    /// 責務: 確定を2回送っても開始通知が1件のままであることを確認します(受け入れ条件 1・3)。
    func testRepeatedConfirmationAnnouncesOnlyOnce() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await driveToAutomaticRecording(harness)

        harness.useCase.recordingDidStart()
        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [F.vin])
    }

    /// 開始要求が辞退・失敗で終わった(終了理由なしの記録終了)後に届いた確定では、何も出しません。
    ///
    /// 責務: 辞退の後の確定で開始通知0件・待機のままであることを確認します(受け入れ条件 2・3)。
    func testConfirmationAfterDeclinedStartIsIgnored() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await driveToAutomaticRecording(harness)
        harness.useCase.recordingDidFinish(endReason: nil)

        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.useCase.state, .standby)
    }

    /// 記録が終わった後に届いた古い確定では、何も出しません。
    ///
    /// 責務: 接続断で終わった記録(再検知の初期化中)へ確定が届いても開始通知0件で、状態が変わらないことを確認します(受け入れ条件 3)。
    func testConfirmationAfterRecordingFinishedIsIgnored() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await driveToAutomaticRecording(harness)
        harness.useCase.recordingDidFinish(endReason: .connectionLost)
        try await harness.wait("再検知の初期化") { harness.initialization.responses.callCount == 2 }
        let state = harness.useCase.state

        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.useCase.state, state)
    }

    /// 前の記録が確定しないまま終わった後、次の自動記録の確定では、その記録の「記録を開始しました」を1回だけ出します。
    ///
    /// 責務: 1回目は辞退、2回目の検知で始めた記録の確定で開始通知が1件であることを確認します(受け入れ条件 2・3)。
    func testConfirmationOfNextRecordingAfterDeclineAnnouncesOnce() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: true)
        try await driveToAutomaticRecording(harness)
        harness.useCase.recordingDidFinish(endReason: nil)
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        try await harness.makeLinkReady()
        try await harness.finishInitialization()
        try await harness.answerRespondingAndWaitForVINRead()
        harness.vinReader.responses.resumeOldest(with: .success(F.vin))
        try await harness.wait("2回目の記録開始要求") { harness.recordingControl.startRequests.count == 2 }

        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [F.vin])
    }

    /// 通知の[記録開始]で手動で始めた記録(自動記録オフ)の確定では、「記録を開始しました」を出しません(現状の維持)。
    ///
    /// 責務: 検知待ちからの手動開始の確定で開始通知0件・記録中のままであることを確認します(受け入れ条件 4)。
    func testConfirmationAfterManualStartFromNotificationDoesNotAnnounce() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: false)
        try await harness.driveToRecording()

        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.useCase.state, .recording(F.detectedVehicle))
    }

    /// 検知前に届いた[記録開始](記録開始の意思)で始めた記録の確定でも、「記録を開始しました」を出しません。
    ///
    /// 責務: 意思で始めた記録は通知の[記録開始]からの開始なので、手動開始と同じく開始通知0件であることを確認します(受け入れ条件 4・6)。
    func testConfirmationAfterIntentStartDoesNotAnnounce() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: false)
        harness.startSignedIn()
        harness.useCase.recordingStartSelected()
        try await harness.makeLinkReady()
        try await harness.finishInitialization()
        try await harness.answerRespondingAndWaitForVINRead()
        harness.vinReader.responses.resumeOldest(with: .success(F.vin))
        try await harness.wait("記録開始要求") { harness.recordingControl.startRequests.count == 1 }

        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
    }

    /// 記録中でない時(検知待ち)に届いた確定では、何も出さず状態も変えません。
    ///
    /// 責務: 検知待ちの確定で開始通知0件・検知待ちのままであることを確認します(受け入れ条件 3)。
    func testConfirmationWhileAwaitingStartIsIgnored() async throws {
        let harness = makeHarness(isAutomaticRecordingEnabled: false)
        try await harness.driveToAwaitingRecordingStart()
        let awaiting = harness.useCase.state

        harness.useCase.recordingDidStart()

        XCTAssertEqual(harness.notifications.presentedRecordingStartedVINs, [])
        XCTAssertEqual(harness.useCase.state, awaiting)
    }
}
