import XCTest
@testable import ProjectZD8

/// 記録終了時の最終表示内容(走行時間の固定値・最大値・終了状態)を確認します。
@MainActor
final class RecordingSessionActivityEndedContentTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_000)

    private func maximums(speed: Double = 80, rpm: Double = 4200, throttle: Double = 55) -> RecordingSessionActivityMaximums {
        var tracker = RecordingSessionActivityMaximumTracker()
        tracker.record([
            RecordingSessionActivityTestSupport.sample(RecordingSessionActivityContent.vehicleSpeedRequest, value: speed),
            RecordingSessionActivityTestSupport.sample(RecordingSessionActivityContent.engineSpeedRequest, value: rpm),
            RecordingSessionActivityTestSupport.sample(RecordingSessionActivityContent.throttlePositionRequest, value: throttle)
        ])
        return tracker.maximums
    }

    private func ended(
        _ phase: LiveTelemetryState.Phase = .idle,
        failureKey: String? = nil,
        endedAt: TimeInterval = 1_600
    ) -> RecordingSessionActivityContent {
        RecordingSessionActivityContent(
            endedTelemetry: RecordingSessionActivityTestSupport.state(phase, failureKey: failureKey, receivedCount: 7),
            vehicleName: "BRZ",
            startedAt: startedAt,
            endedAt: Date(timeIntervalSince1970: endedAt),
            maximums: maximums(),
            vehiclePhotoFileName: "p.jpg"
        )
    }

    /// 責務: 走行時間が開始〜終了の固定値になることを確認します。
    func testDrivingDurationIsEndMinusStart() {
        XCTAssertEqual(ended(endedAt: 1_600).endedSummary?.drivingDuration, 600)
    }

    /// 責務: 終了が開始と同時刻なら0秒、終了が開始より前でも負にならないことを確認します。
    func testDrivingDurationBoundaries() {
        XCTAssertEqual(ended(endedAt: 1_000).endedSummary?.drivingDuration, 0)
        XCTAssertEqual(ended(endedAt: 900).endedSummary?.drivingDuration, 0)
    }

    /// 責務: 終了表示が項目ごとの最大値を持つことを確認します。
    func testEndedContentCarriesMaximums() {
        let summary = ended().endedSummary
        XCTAssertEqual(summary?.maximums.vehicleSpeed, .value(80))
        XCTAssertEqual(summary?.maximums.engineSpeed, .value(4200))
        XCTAssertEqual(summary?.maximums.throttlePosition, .value(55))
    }

    /// 責務: 終了表示が終了状態(切断操作なし・タイマー停止)を示すことを確認します。
    func testEndedContentFlags() {
        let content = ended()
        XCTAssertTrue(content.isEnded)
        XCTAssertFalse(content.showsDisconnectAction)
        XCTAssertFalse(content.isTimerRunning)
    }

    /// 責務: 終了理由(待機・失敗・一時停止中の切断など)に関わらず終了表示になることを確認します。
    func testEveryEndReasonProducesEndedContent() {
        for phase in [LiveTelemetryState.Phase.idle, .failed, .paused, .stopping] {
            let content = ended(phase, failureKey: phase == .idle ? "live_activity.status.grace_expired" : nil)
            XCTAssertTrue(content.isEnded, "\(phase)")
            XCTAssertFalse(content.showsDisconnectAction, "\(phase)")
            XCTAssertFalse(content.isTimerRunning, "\(phase)")
            XCTAssertNotNil(content.endedSummary, "\(phase)")
        }
    }

    /// 責務: 記録中の内容は終了表示ではなく、切断操作とタイマーを持つことを確認します。
    func testRecordingContentIsNotEnded() {
        let content = RecordingSessionActivityContent(
            telemetry: RecordingSessionActivityTestSupport.state(.loaded),
            vehicleName: "BRZ", startedAt: startedAt, vehiclePhotoFileName: nil
        )
        XCTAssertFalse(content.isEnded)
        XCTAssertNil(content.endedSummary)
        XCTAssertTrue(content.showsDisconnectAction)
        XCTAssertTrue(content.isTimerRunning)
    }

    /// 責務: 終了表示でも車両名・写真・開始時刻・受信件数を保つことを確認します。
    func testEndedContentKeepsIdentityFields() {
        let content = ended()
        XCTAssertEqual(content.vehicle, .named("BRZ"))
        XCTAssertEqual(content.vehiclePhotoFileName, "p.jpg")
        XCTAssertEqual(content.startedAt, startedAt)
        XCTAssertEqual(content.receivedResponseCount, 7)
    }
}
