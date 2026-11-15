import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` の終了と、境界の失敗が外へ出ないことのテストです。
@MainActor
final class RecordingSessionActivityUseCaseEndTests: XCTestCase {
    /// 責務: セッションが待機へ移ると最終状態を載せて終了を呼ぶことを確認します。
    func testIdleEndsActivityWithFinalContent() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 42))
        await harness.send(harness.state(.idle, speed: 42))
        XCTAssertEqual(harness.activity.endedContents.count, 1)
        XCTAssertEqual(harness.activity.endedContents[0].statusKey, "live_activity.status.ended")
        XCTAssertEqual(harness.activity.endedContents[0].vehicleSpeed, .value(42))
        XCTAssertFalse(harness.activity.isPresenting)
    }

    /// 責務: 取得が失敗へ移ると失敗状態を載せて終了を呼ぶことを確認します。
    func testFailedEndsActivityWithFailedStatus() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 42))
        await harness.send(harness.state(.failed, speed: 42))
        XCTAssertEqual(harness.activity.endedContents.count, 1)
        XCTAssertEqual(harness.activity.endedContents[0].statusKey, "live_activity.status.failed")
        XCTAssertEqual(harness.activity.endedContents[0].statusTone, .warning)
    }

    /// 責務: 開始が throw しても例外を出さず、診断へ開始として1件残すことを確認します。
    func testStartFailureIsRecordedOnceAsStart() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.activity.startError = SessionActivityPortError.notAuthorized
        await harness.send(harness.state(.loaded, speed: 10))
        XCTAssertEqual(harness.diagnostics.failedOperations, [.start])
    }

    /// 責務: 更新が throw しても例外を出さず、診断へ更新として1件残すことを確認します。
    func testUpdateFailureIsRecordedOnceAsUpdate() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.updateError = SessionActivityPortError.notPresenting
        harness.currentDate = harness.currentDate.addingTimeInterval(5)
        await harness.send(harness.state(.loaded, speed: 20))
        XCTAssertEqual(harness.diagnostics.failedOperations, [.update])
    }

    /// 責務: 終了が throw しても例外を出さず、診断へ終了として1件残すことを確認します。
    func testEndFailureIsRecordedOnceAsEnd() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.endError = SessionActivityPortError.notPresenting
        await harness.send(harness.state(.idle, speed: 10))
        XCTAssertEqual(harness.diagnostics.failedOperations, [.end])
    }

    /// 責務: 開始が失敗しても、その後の記録の更新処理が続き新しい開始を妨げないことを確認します。
    func testStartFailureDoesNotBlockLaterForegroundStart() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.activity.startError = SessionActivityPortError.notAuthorized
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.startError = nil
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.startedContents.count, 2)
        XCTAssertTrue(harness.activity.isPresenting)
    }
}
