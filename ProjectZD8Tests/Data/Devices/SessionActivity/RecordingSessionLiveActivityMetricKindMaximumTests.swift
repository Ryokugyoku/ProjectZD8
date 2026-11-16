import XCTest
@testable import ProjectZD8

/// `RecordingSessionLiveActivityMetricKind.maximum(in:)` が種類ごとの最大値を返すことを確認します。
final class RecordingSessionLiveActivityMetricKindMaximumTests: XCTestCase {
    private typealias Summary = RecordingSessionActivityAttributes.EndedSummary

    /// 責務: 3項目が異なる値でも、種類ごとに対応する最大値を返すことを確認します。
    func testReturnsMaximumForEachKind() {
        let summary = Summary(
            drivingSeconds: 10, maximumVehicleSpeed: .value(1),
            maximumEngineSpeed: .value(2), maximumThrottlePosition: .value(3)
        )
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.vehicleSpeed.maximum(in: summary), .value(1))
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.engineSpeed.maximum(in: summary), .value(2))
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.throttlePosition.maximum(in: summary), .value(3))
    }

    /// 責務: unavailable の項目は、その項目だけ unavailable を返すことを確認します。
    func testUnavailableIsReturnedOnlyForItsKind() {
        let summary = Summary(
            drivingSeconds: 0, maximumVehicleSpeed: .unavailable,
            maximumEngineSpeed: .value(2), maximumThrottlePosition: .unavailable
        )
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.vehicleSpeed.maximum(in: summary), .unavailable)
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.engineSpeed.maximum(in: summary), .value(2))
        XCTAssertEqual(RecordingSessionLiveActivityMetricKind.throttlePosition.maximum(in: summary), .unavailable)
    }
}
