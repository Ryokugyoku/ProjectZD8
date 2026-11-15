import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` の開始・前面復帰・システムによる終了のテストです。
@MainActor
final class RecordingSessionActivityUseCaseTests: XCTestCase {
    /// 責務: 前面で記録が始まると表示を1回開始することを確認します。
    func testRecordingStartedInForegroundStartsActivity() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        XCTAssertEqual(harness.activity.startedContents.count, 1)
        XCTAssertTrue(harness.activity.isPresenting)
    }

    /// 責務: バックグラウンドで始まった記録は開始せず、次の前面復帰で開始することを確認します。
    func testRecordingStartedInBackgroundStartsOnNextForeground() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        harness.foreground = false
        await harness.send(harness.state(.loaded, speed: 10))
        XCTAssertEqual(harness.activity.startedContents.count, 0)
        harness.foreground = true
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.startedContents.count, 1)
    }

    /// 責務: 表示が出ている間の前面復帰は二重に開始しないことを確認します。
    func testForegroundWhilePresentingDoesNotStartTwice() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        await harness.enterForeground()
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.startedContents.count, 1)
    }

    /// 責務: 記録していないときの前面復帰は何も開始しないことを確認します。
    func testForegroundWithoutRecordingStartsNothing() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.startedContents.count, 0)
    }

    /// 責務: システムが表示を終了しても記録は続き、次の前面復帰で再表示することを確認します。
    func testSystemDismissalKeepsRecordingAndRestartsOnForeground() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.activity.simulateSystemDismissal()
        harness.currentDate = harness.currentDate.addingTimeInterval(10)
        await harness.send(harness.state(.loaded, speed: 50))
        XCTAssertEqual(harness.activity.updatedContents.count, 0)
        XCTAssertEqual(harness.activity.endedContents.count, 0)
        XCTAssertTrue(harness.diagnostics.failedOperations.isEmpty)
        await harness.enterForeground()
        XCTAssertEqual(harness.activity.startedContents.count, 2)
        XCTAssertEqual(harness.activity.startedContents[1].vehicleSpeed, .value(50))
    }
}
