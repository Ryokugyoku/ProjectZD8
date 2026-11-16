import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` のサインアウトを、待機・初期化・車両確認・検知済み・記録中・終了の各状態で検証します。
@MainActor
final class AdapterLinkSupervisionUseCaseSignOutTests: XCTestCase {
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

    /// サインアウトしてリンク停止・通知取り下げが起きたことを検証します。
    ///
    /// 責務: 停止1回・取り下げの増加・リンクを開始し直さないことを確認します。
    private func signOutAndAssertLinkStopped(
        _ harness: AdapterLinkSupervisionHarness, file: StaticString = #filePath, line: UInt = #line
    ) {
        let dismissals = harness.notifications.dismissCount
        let starts = harness.link.startedPreferences.count
        harness.useCase.authenticationDidChange(isSignedIn: false)
        XCTAssertEqual(harness.link.stopCount, 1, "リンク停止", file: file, line: line)
        XCTAssertGreaterThan(harness.notifications.dismissCount, dismissals, "通知の取り下げ", file: file, line: line)
        XCTAssertEqual(harness.link.startedPreferences.count, starts, "リンクの再開始", file: file, line: line)
    }

    /// 待機(リンク未 `ready`)でサインアウトするとリンクを止めて待機のままです。
    ///
    /// 責務: 停止・取り下げ・記録停止要求なしを確認します。
    func testSignOutInStandby() {
        let harness = makeHarness()
        harness.startSignedIn()
        harness.link.emit(.connecting)
        signOutAndAssertLinkStopped(harness)
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0)
    }

    /// 初期化中にサインアウトすると待機へ戻り、後から届いた初期化成功で確認を始めません。
    ///
    /// 責務: 停止・待機・古い初期化結果の無視を確認します。
    func testSignOutWhileInitializing() async throws {
        let harness = makeHarness()
        harness.startSignedIn()
        try await harness.makeLinkReady()
        signOutAndAssertLinkStopped(harness)
        XCTAssertEqual(harness.useCase.state, .standby)

        harness.initialization.responses.resumeOldest(with: .success(F.evidence))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.vehicleResponse.timeouts, [])
    }

    /// 車両確認中にサインアウトすると待機へ戻り、後から届いた応答ありで検知しません。
    ///
    /// 責務: 停止・待機・古い確認結果の無視(VIN読取・通知なし)を確認します。
    func testSignOutWhileConfirmingVehicle() async throws {
        let harness = makeHarness()
        try await harness.driveToConfirming()
        signOutAndAssertLinkStopped(harness)
        XCTAssertEqual(harness.useCase.state, .standby)

        harness.vehicleResponse.responses.resumeOldest(with: .success(.responding))
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.vinReader.responses.callCount, 0)
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs, [])
    }

    /// 検知済みでサインアウトすると検知通知を取り下げて待機へ戻り、後の[記録開始]で記録を始めません。
    ///
    /// 責務: 停止・取り下げ・待機・記録開始要求なしを確認します。
    func testSignOutWhileVehicleDetected() async throws {
        let harness = makeHarness()
        try await harness.driveToAwaitingRecordingStart()
        signOutAndAssertLinkStopped(harness)
        XCTAssertEqual(harness.useCase.state, .standby)

        harness.useCase.recordingStartSelected()
        XCTAssertEqual(harness.recordingControl.startRequests, [])
    }

    /// 記録中にサインアウトすると停止を要求して終了へ移り、記録終了の通知後に待機へ戻ります。
    ///
    /// 責務: 停止要求1回・リンク停止・終了・記録終了後の待機を確認します。
    func testSignOutWhileRecording() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        signOutAndAssertLinkStopped(harness)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 1)
        XCTAssertEqual(harness.useCase.state, .finishing)

        harness.useCase.recordingDidFinish(endReason: nil)
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 1)
    }

    /// 終了中(手動接続の開始で停止要求済み)にサインアウトすると、停止要求を重ねずにリンクを止め、記録終了後に待機へ戻ります。
    ///
    /// 責務: 停止要求が1回のまま・リンク停止・終了のまま・記録終了後の待機を確認します。
    /// 終了中へは手動接続の開始で移します(リンク断では記録中のままのため。U2 受け入れ条件 1)。
    func testSignOutWhileFinishing() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.useCase.externalAdapterUseDidBegin()
        XCTAssertEqual(harness.useCase.state, .finishing)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 1)

        signOutAndAssertLinkStopped(harness)
        XCTAssertEqual(harness.useCase.state, .finishing)
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 1)

        harness.useCase.recordingDidFinish(endReason: nil)
        XCTAssertEqual(harness.useCase.state, .standby)
    }

    /// リンク断で記録中のままのところへサインアウトすると、従来どおり停止を要求してリンクを止め、終了へ移ります。
    ///
    /// 責務: リンク断では停止要求0回、サインアウトで停止要求1回・リンク停止・終了になることを確認します(U2 受け入れ条件 1・9)。
    func testSignOutAfterLinkLossWhileRecordingRequestsStop() async throws {
        let harness = makeHarness()
        try await harness.driveToRecording()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertEqual(harness.recordingControl.stopRequestCount, 0, "リンク断では止めない")

        signOutAndAssertLinkStopped(harness)

        XCTAssertEqual(harness.recordingControl.stopRequestCount, 1)
        XCTAssertEqual(harness.useCase.state, .finishing)
    }
}
