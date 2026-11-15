import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` が、ユーザー切断で記録が終わった後は同じリンク接続のあいだ再び記録を始めず、
/// リンクが切れて戻れば初期化し直し、他の終了理由では従来どおり前面復帰で初期化することを検証します。
@MainActor
final class AdapterLinkSupervisionUseCaseUserStopTests: XCTestCase {
    /// テスト中に組み立てた手段です。終了時に保留を終わらせます。
    private var harnesses: [AdapterLinkSupervisionHarness] = []

    /// 責務: 保留中の非同期呼び出しを全て終わらせます。
    override func tearDown() async throws {
        harnesses.forEach { $0.finishAllPending() }
        harnesses.removeAll()
        try await super.tearDown()
    }

    /// 責務: 自動記録オンの手段を組み立て、検知から自動で記録中になるまで進めます。
    private func makeRecordingHarness() async throws -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness(isAutomaticRecordingEnabled: true)
        harnesses.append(harness)
        try await harness.driveToConfirming()
        try await harness.answerRespondingAndWaitForVINRead()
        harness.vinReader.responses.resumeOldest(with: .success(AdapterLinkSupervisionFixtures.vin))
        try await harness.wait("記録開始要求") { harness.recordingControl.startRequests.count == 1 }
        XCTAssertTrue(harness.isRecording)
        return harness
    }

    /// 検証: 初期化・記録開始要求が増えておらず、抑止のため待機でも終了中でもないこと。
    ///
    /// 責務: 抑止中に何も起きていないことを回数と状態で確認します。
    private func assertNothingRestarted(_ harness: AdapterLinkSupervisionHarness, file: StaticString = #filePath, line: UInt = #line) async throws {
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 1, "初期化が増えた", file: file, line: line)
        XCTAssertEqual(harness.recordingControl.startRequests.count, 1, "記録開始要求が増えた", file: file, line: line)
        XCTAssertEqual(harness.useCase.state, .heldAfterUserStop, file: file, line: line)
    }

    /// ユーザー切断で記録が終わった後に前面へ戻っても、初期化も記録開始もしません。
    ///
    /// 責務: 前面復帰後に初期化・記録開始要求が増えないことを確認します。
    func testForegroundAfterUserDisconnectDoesNotRestart() async throws {
        let harness = try await makeRecordingHarness()
        harness.useCase.recordingDidFinish(endReason: .userDisconnected)
        harness.useCase.appDidBecomeActive()
        try await assertNothingRestarted(harness)
    }

    /// ユーザー切断で記録が終わった後にリンクの ready が再通知されても、初期化も記録開始もしません。
    ///
    /// 責務: ready の再通知後に初期化・記録開始要求が増えないことを確認します。
    func testLinkReadyReannouncementAfterUserDisconnectDoesNotRestart() async throws {
        let harness = try await makeRecordingHarness()
        harness.useCase.recordingDidFinish(endReason: .userDisconnected)
        harness.link.emit(.ready)
        harness.useCase.appDidBecomeActive()
        harness.link.emit(.ready)
        try await assertNothingRestarted(harness)
    }

    /// 抑止の後にリンクが切れて ready に戻ると、初期化が1回呼ばれます。
    ///
    /// 責務: 再接続で初期化が2回目の呼び出しになり、前面復帰では増えないことを確認します。
    func testReconnectAfterUserDisconnectInitializesOnce() async throws {
        let harness = try await makeRecordingHarness()
        harness.useCase.recordingDidFinish(endReason: .userDisconnected)
        harness.useCase.appDidBecomeActive()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        XCTAssertEqual(harness.useCase.state, .standby)
        try await harness.makeLinkReady()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 2)
    }

    /// 車両が応答しなくなって記録が終わった後は抑止せず、リンクが `ready` なら前面復帰を待たずに初期化し直します。
    ///
    /// 責務: ユーザー切断以外の理由では抑止せず、終了の時点で初期化が2回目になり `.initializing(linkReadyAt: 終了時刻)` になることを確認します(U3 受け入れ条件 13)。
    func testVehicleNoResponseFinishInitializesAgainWithoutForeground() async throws {
        let harness = try await makeRecordingHarness()
        harness.useCase.recordingDidFinish(endReason: .vehicleNoResponse)
        try await harness.wait("初期化のやり直し") { harness.initialization.responses.callCount == 2 }
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))
    }
}
