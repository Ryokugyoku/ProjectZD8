import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityContentStateMapper` の終了表示(`endedSummary`)の変換を確認します。
@MainActor
final class RecordingSessionActivityContentStateMapperEndedSummaryTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_000)

    private func recording() -> RecordingSessionActivityContent {
        RecordingSessionActivityContent(
            telemetry: RecordingSessionActivityTestSupport.state(.loaded),
            vehicleName: "BRZ", startedAt: startedAt, vehiclePhotoFileName: nil
        )
    }

    private func ended(_ tracker: RecordingSessionActivityMaximumTracker, endedAt: TimeInterval) -> RecordingSessionActivityContent {
        RecordingSessionActivityContent(
            endedTelemetry: RecordingSessionActivityTestSupport.state(.idle),
            vehicleName: "BRZ", startedAt: startedAt, endedAt: Date(timeIntervalSince1970: endedAt),
            maximums: tracker.maximums, vehiclePhotoFileName: nil
        )
    }

    /// 責務: 記録中の内容では `endedSummary` が nil で、JSON にキーが出ないことを確認します。
    func testRecordingContentHasNoEndedSummary() throws {
        let state = RecordingSessionActivityContentStateMapper().contentState(from: recording())
        XCTAssertNil(state.endedSummary)
        XCTAssertFalse(state.isEnded)
        let json = try String(decoding: JSONEncoder().encode(state), as: UTF8.self)
        XCTAssertFalse(json.contains("endedSummary"), json)
    }

    /// 責務: 終了内容では走行秒数と3つの最大値(値あり・unavailable)が写ることを確認します。
    func testEndedContentMapsDurationAndMaximums() {
        var tracker = RecordingSessionActivityMaximumTracker()
        tracker.record([
            RecordingSessionActivityTestSupport.sample(RecordingSessionActivityContent.vehicleSpeedRequest, value: 88),
            RecordingSessionActivityTestSupport.sample(RecordingSessionActivityContent.engineSpeedRequest, value: 6100)
        ])
        let state = RecordingSessionActivityContentStateMapper().contentState(from: ended(tracker, endedAt: 1_450))
        XCTAssertTrue(state.isEnded)
        XCTAssertEqual(state.endedSummary?.drivingSeconds, 450)
        XCTAssertEqual(state.endedSummary?.maximumVehicleSpeed, .value(88))
        XCTAssertEqual(state.endedSummary?.maximumEngineSpeed, .value(6100))
        XCTAssertEqual(state.endedSummary?.maximumThrottlePosition, .unavailable)
    }

    /// 責務: 終了表示を含む `ContentState` が JSON で往復しても保たれることを確認します。
    func testEndedSummarySurvivesJSONRoundTrip() throws {
        let state = RecordingSessionActivityContentStateMapper().contentState(
            from: ended(RecordingSessionActivityMaximumTracker(), endedAt: 1_060)
        )
        let decoded = try JSONDecoder().decode(
            RecordingSessionActivityAttributes.ContentState.self, from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.endedSummary?.drivingSeconds, 60)
    }
}
