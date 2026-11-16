import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityUseCase` が終了時に終了表示と5分後の消去時刻で `end` を呼ぶことのテストです。
@MainActor
final class RecordingSessionActivityUseCaseEndedDisplayTests: XCTestCase {
    private func loaded(speed: Double, rpm: Double? = nil) -> LiveTelemetryState {
        var samples = [RecordingSessionActivityTestSupport.sample(RecordingSessionActivityContent.vehicleSpeedRequest, value: speed)]
        if let rpm {
            samples.append(RecordingSessionActivityTestSupport.sample(RecordingSessionActivityContent.engineSpeedRequest, value: rpm))
        }
        return RecordingSessionActivityTestSupport.state(.loaded, samples: samples)
    }

    /// 責務: 終了時に、走行時間・最大値を持つ終了表示が5分後の消去時刻で渡されることを確認します。
    func testEndPassesEndedContentAndDismissAtFiveMinutesLater() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(loaded(speed: 30, rpm: 2000))
        await harness.send(loaded(speed: 80, rpm: 5000))
        await harness.send(loaded(speed: 50, rpm: 3000))
        harness.currentDate = Date(timeIntervalSince1970: 1_600)
        await harness.send(harness.state(.idle, speed: 50))

        XCTAssertEqual(harness.activity.endedContents.count, 1)
        let content = harness.activity.endedContents[0]
        XCTAssertTrue(content.isEnded)
        XCTAssertFalse(content.showsDisconnectAction)
        XCTAssertFalse(content.isTimerRunning)
        XCTAssertEqual(content.endedSummary?.drivingDuration, 600)
        XCTAssertEqual(content.endedSummary?.maximums.vehicleSpeed, .value(80), "間引かれた更新の値も最大値に含める")
        XCTAssertEqual(content.endedSummary?.maximums.engineSpeed, .value(5000))
        XCTAssertEqual(harness.activity.endedDismissDates, [Date(timeIntervalSince1970: 1_900)])
    }

    /// 責務: 記録中の更新は終了表示にならず、切断操作とタイマーを保つことを確認します。
    func testUpdatesWhileRecordingAreNotEnded() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(loaded(speed: 30))
        harness.currentDate = harness.currentDate.addingTimeInterval(5)
        await harness.send(loaded(speed: 40))
        let contents = harness.activity.startedContents + harness.activity.updatedContents
        XCTAssertFalse(contents.isEmpty)
        XCTAssertTrue(contents.allSatisfy { !$0.isEnded && $0.showsDisconnectAction && $0.isTimerRunning })
    }

    /// 責務: 失敗で終わっても終了表示と5分後の消去時刻で閉じることを確認します。
    func testFailedEndAlsoUsesEndedDisplay() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(loaded(speed: 60))
        harness.currentDate = Date(timeIntervalSince1970: 1_120)
        await harness.send(harness.state(.failed, speed: 60))

        XCTAssertEqual(harness.activity.endedContents.first?.isEnded, true)
        XCTAssertEqual(harness.activity.endedContents.first?.endedSummary?.drivingDuration, 120)
        XCTAssertEqual(harness.activity.endedDismissDates, [Date(timeIntervalSince1970: 1_420)])
    }

    /// 責務: 次のセッションの最大値が前のセッションから引き継がれないことを確認します。
    func testMaximumsResetAtNextSession() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(loaded(speed: 200))
        await harness.send(harness.state(.idle))
        harness.currentDate = Date(timeIntervalSince1970: 5_000)
        await harness.send(loaded(speed: 20))
        harness.currentDate = Date(timeIntervalSince1970: 5_100)
        await harness.send(harness.state(.idle))

        XCTAssertEqual(harness.activity.endedContents.count, 2)
        XCTAssertEqual(harness.activity.endedContents[1].endedSummary?.maximums.vehicleSpeed, .value(20))
        XCTAssertEqual(harness.activity.endedContents[1].endedSummary?.drivingDuration, 100)
        XCTAssertEqual(harness.activity.endedDismissDates[1], Date(timeIntervalSince1970: 5_400))
    }

    /// 責務: 観測が一度も無いまま終わった場合、最大値が未取得の終了表示になることを確認します。
    func testEndWithoutSamplesHasUnavailableMaximums() async {
        let harness = RecordingSessionActivityUseCaseHarness()
        await harness.send(RecordingSessionActivityTestSupport.state(.loaded))
        await harness.send(harness.state(.idle))
        XCTAssertEqual(harness.activity.endedContents.first?.endedSummary?.maximums.vehicleSpeed, .unavailable)
    }
}
