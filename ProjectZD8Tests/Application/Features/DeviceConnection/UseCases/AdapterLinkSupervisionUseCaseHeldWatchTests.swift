import XCTest
@testable import ProjectZD8

/// `AdapterLinkSupervisionUseCase` の、ユーザー切断後の見張り・手動接続との排他・記録中と終了処理中の沈黙・記録終了後のやり直しの対象を、fake で検証します。
///
/// 仕様: U3 受け入れ条件 8〜14 と管理チャットの決定 v〜vii。時間は fake の時計の `now` を、確認の結果を返す前に進めて表します。
@MainActor
final class AdapterLinkSupervisionUseCaseHeldWatchTests: XCTestCase {
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

    /// 記録中まで進めた手段を返します。
    ///
    /// 責務: 手段を組み立てて終了処理の対象に加え、記録中まで進めます。
    /// - Returns: 記録中の手段。
    private func recordingHarness(file: StaticString = #filePath, line: UInt = #line) async throws -> AdapterLinkSupervisionHarness {
        let harness = AdapterLinkSupervisionHarness()
        harnesses.append(harness)
        try await harness.driveToRecording(file: file, line: line)
        return harness
    }

    /// ユーザー切断で記録を終え、最初の見張りの確認が送られるまで進めた手段を返します。
    ///
    /// 責務: リンク `ready` のままユーザー切断で終え、`.heldWatch` の確認が1件増えるまで待ちます。
    /// - Returns: 見張り中の手段。
    private func watchingHarness(file: StaticString = #filePath, line: UInt = #line) async throws -> AdapterLinkSupervisionHarness {
        let harness = try await recordingHarness(file: file, line: line)
        let confirmations = harness.vehicleResponse.timeouts.count
        harness.useCase.recordingDidFinish(endReason: .userDisconnected)
        try await harness.wait("最初の見張りの確認", file: file, line: line) {
            harness.vehicleResponse.timeouts.count == confirmations + 1
        }
        XCTAssertEqual(harness.vehicleResponse.timeouts.last, .heldWatch, file: file, line: line)
        return harness
    }

    /// 見張りの確認へ結果を返し、次の見張りの確認が送られるまで待ちます(1回の確認に2秒かかったとします)。
    ///
    /// 責務: 時計を2秒進めて結果を返し、`.heldWatch` の確認が1件増えるまで待ちます。
    /// - Parameters:
    ///   - harness: 見張りの確認が1件保留されている手段。
    ///   - result: 返す結果。
    private func answerWatch(
        _ harness: AdapterLinkSupervisionHarness,
        with result: Result<VehicleResponseOutcome, any Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let confirmations = harness.vehicleResponse.timeouts.count
        harness.clock.now = harness.clock.now.addingTimeInterval(2)
        harness.vehicleResponse.responses.resumeOldest(with: result, file: file, line: line)
        try await harness.wait("次の見張りの確認", file: file, line: line) { harness.vehicleResponse.timeouts.count == confirmations + 1 }
        XCTAssertEqual(harness.vehicleResponse.timeouts.last, .heldWatch, file: file, line: line)
    }

    /// 見張り中に ECU の無応答が連続2回になったら抑止を解き、初期化からやり直します。1回目では解きません。
    ///
    /// 責務: 1回目の後は抑止のまま初期化1回、2回目の後は初期化2回・`.initializing(linkReadyAt: その時刻)` になることを確認します(仕様 10)。
    func testTwoConsecutiveNoResponsesReleaseHold() async throws {
        let harness = try await watchingHarness()
        try await answerWatch(harness, with: .success(.noResponse))
        XCTAssertTrue(harness.useCase.state.isHeldAfterUserStop)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)

        harness.clock.now = harness.clock.now.addingTimeInterval(2)
        harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
        try await harness.wait("初期化のやり直し") { harness.initialization.responses.callCount == 2 }
        XCTAssertEqual(harness.useCase.state, .initializing(linkReadyAt: harness.clock.now))
        XCTAssertEqual(harness.notifications.presentedVehicleDetectedVINs.count, 1, "解いただけでは通知しない")
    }

    /// 無応答の間に ECU の応答があれば数え直し、その後の無応答1回では抑止を解きません。
    ///
    /// 責務: 無応答 → 応答 → 無応答 の後も抑止のままで、初期化が増えないことを確認します(仕様 8・10)。
    func testResponseBetweenNoResponsesKeepsHold() async throws {
        let harness = try await watchingHarness()
        try await answerWatch(harness, with: .success(.noResponse))
        try await answerWatch(harness, with: .success(.responding))
        try await answerWatch(harness, with: .success(.noResponse))
        XCTAssertTrue(harness.useCase.state.isHeldAfterUserStop)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
        XCTAssertEqual(harness.recordingControl.startRequests.count, 1, "同じ走行の間は記録を始めない")
    }

    /// 見張りの確認の失敗(throw)は無応答に数えません。失敗が2回続いても抑止を解かず、その後の無応答1回でも解きません。
    ///
    /// 責務: 失敗 → 失敗 → 無応答 の後も抑止のままで、初期化が増えないことを確認します(決定 vii)。
    func testConfirmationFailuresAreNotCountedAsNoResponse() async throws {
        let harness = try await watchingHarness()
        try await answerWatch(harness, with: .failure(AdapterLinkWriteError.linkLost))
        try await answerWatch(harness, with: .failure(AdapterLinkWriteError.linkLost))
        try await answerWatch(harness, with: .success(.noResponse))
        XCTAssertTrue(harness.useCase.state.isHeldAfterUserStop)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
    }

    /// 見張り中に手動接続が始まったら、使用中は見張りの確認を送りません(結果が届いても、前面復帰しても)。
    ///
    /// 責務: 手動接続の開始後に、保留中の結果を返しても前面復帰しても見張りの確認が増えないことを確認します(決定 v)。
    func testExternalAdapterUseStopsWatchConfirmations() async throws {
        let harness = try await watchingHarness()
        let confirmations = harness.vehicleResponse.timeouts.count
        harness.useCase.externalAdapterUseDidBegin()
        harness.clock.now = harness.clock.now.addingTimeInterval(2)
        harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, confirmations)
        XCTAssertTrue(harness.useCase.state.isHeldAfterUserStop)
    }

    /// 手動接続が終わった時、まだ抑止中でリンクが `ready` なら、前面復帰を待たずに見張りを再開します。
    ///
    /// 責務: 手動接続の終了で `.heldWatch` の確認が1件増えることを確認します(決定 vi)。
    func testExternalAdapterUseEndResumesWatch() async throws {
        let harness = try await watchingHarness()
        harness.useCase.externalAdapterUseDidBegin()
        harness.vehicleResponse.responses.failAllPending()
        try await BLEBoundedWaiter.settle()
        let confirmations = harness.vehicleResponse.timeouts.count

        harness.useCase.externalAdapterUseDidEnd()

        try await harness.wait("見張りの再開") { harness.vehicleResponse.timeouts.count == confirmations + 1 }
        XCTAssertEqual(harness.vehicleResponse.timeouts.last, .heldWatch)
    }

    /// 背面へ移った後は窓切れで休止し、前面へ戻ったら窓を取り直して確認を再開します。
    ///
    /// 責務: 前面復帰 → 背面移行 → 窓切れの無応答で `.paused`、続く前面復帰で確認が増えて `.probing` になることを確認します(仕様 5・6)。
    func testBackgroundPausesOnWindowEndAndForegroundResumes() async throws {
        let harness = AdapterLinkSupervisionHarness()
        harnesses.append(harness)
        try await harness.driveToConfirming()
        harness.useCase.appDidBecomeActive()
        harness.useCase.appDidEnterBackground()
        harness.clock.now = F.date(F.windowSeconds)
        harness.vehicleResponse.responses.resumeOldest(with: .success(.noResponse))
        try await harness.wait("休止") { harness.isConfirming(.paused) }

        harness.useCase.appDidBecomeActive()
        try await harness.wait("再開の確認") { harness.vehicleResponse.timeouts.count == 2 }
        XCTAssertTrue(harness.isConfirming(.probing))
    }

    /// 記録中は、リンクの再接続や前面復帰があっても、監視は初期化も確認も送りません。
    ///
    /// 責務: 記録中のリンク断 → `ready` と前面復帰の後も、初期化・確認の呼び出しが増えないことを確認します(仕様 14)。
    func testNothingIsSentWhileRecording() async throws {
        let harness = try await recordingHarness()
        harness.link.emit(.disconnected(.peripheralDisconnected(errorDescription: nil)))
        harness.link.emit(.connecting)
        harness.link.emit(.ready)
        harness.useCase.appDidBecomeActive()
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 1)
    }

    /// 監視が停止を要求した記録(終了中から終わる)は、終了の後に検知をやり直さず、終了中も何も送りません。
    ///
    /// 責務: 手動接続の開始で終了中にし、手動接続の終了・前面復帰・置き換えでの記録終了の後も初期化・確認が増えないことを確認します(仕様 13・14)。
    func testRecordingStoppedBySupervisionDoesNotRestartDetection() async throws {
        let harness = try await recordingHarness()
        harness.useCase.externalAdapterUseDidBegin()
        XCTAssertEqual(harness.useCase.state, .finishing)
        harness.useCase.externalAdapterUseDidEnd()

        harness.useCase.recordingDidFinish(endReason: .superseded)
        try await BLEBoundedWaiter.settle()

        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
        XCTAssertEqual(harness.vehicleResponse.timeouts.count, 1)
    }

    /// 終了理由の無い記録の終了(記録が始まらなかった・辞退した)では、検知をやり直しません。
    ///
    /// 責務: 理由 `nil` の終了の後に待機のままで、初期化が増えないことを確認します(仕様 13 の対象外)。
    func testFinishWithoutEndReasonDoesNotRestartDetection() async throws {
        let harness = try await recordingHarness()
        harness.useCase.recordingDidFinish(endReason: nil)
        try await BLEBoundedWaiter.settle()
        XCTAssertEqual(harness.useCase.state, .standby)
        XCTAssertEqual(harness.initialization.responses.callCount, 1)
    }
}
