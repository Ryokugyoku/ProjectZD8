import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` の更新の間引きのテストです。
@MainActor
final class RecordingSessionActivityUseCaseUpdateTests: XCTestCase {
    /// 責務: 前回送信から3秒未満の数値変化は送らないことを確認します。
    func testNumericChangeWithinThreeSecondsIsNotSent() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.currentDate = harness.currentDate.addingTimeInterval(2.9)
        await harness.send(harness.state(.loaded, speed: 20))
        XCTAssertEqual(harness.activity.updatedContents.count, 0)
    }

    /// 責務: 3秒以上経てば数値変化を送ることを確認します。
    func testNumericChangeAfterThreeSecondsIsSent() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.currentDate = harness.currentDate.addingTimeInterval(3)
        await harness.send(harness.state(.loaded, speed: 20))
        XCTAssertEqual(harness.activity.updatedContents.count, 1)
        XCTAssertEqual(harness.activity.updatedContents[0].vehicleSpeed, .value(20))
    }

    /// 責務: 状態の変化は3秒を待たず即時に送ることを確認します。
    func testStatusChangeIsSentImmediately() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.currentDate = harness.currentDate.addingTimeInterval(0.1)
        await harness.send(harness.state(.paused, speed: 10))
        XCTAssertEqual(harness.activity.updatedContents.count, 1)
        XCTAssertEqual(harness.activity.updatedContents[0].statusTone, .warning)
    }

    /// 責務: 同じ内容は時間が経っても送らないことを確認します。
    func testIdenticalContentIsNeverSent() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(harness.state(.loaded, speed: 10))
        harness.currentDate = harness.currentDate.addingTimeInterval(60)
        await harness.send(harness.state(.loaded, speed: 10))
        XCTAssertEqual(harness.activity.updatedContents.count, 0)
    }
}
