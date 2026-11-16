import XCTest
@testable import ProjectZD8

/// `RecordingSessionActivityMaximumTracker` の項目別最大値の集計を確認します。
final class RecordingSessionActivityMaximumTrackerTests: XCTestCase {
    private let speed = RecordingSessionActivityContent.vehicleSpeedRequest
    private let rpm = RecordingSessionActivityContent.engineSpeedRequest
    private let throttle = RecordingSessionActivityContent.throttlePositionRequest

    /// 責務: 観測を受け取る前は全項目が未取得であることを確認します。
    func testNoValuesYieldsUnavailable() {
        let tracker = RecordingSessionActivityMaximumTracker()
        XCTAssertEqual(tracker.maximums.vehicleSpeed, .unavailable)
        XCTAssertEqual(tracker.maximums.engineSpeed, .unavailable)
        XCTAssertEqual(tracker.maximums.throttlePosition, .unavailable)
    }

    /// 責務: 単調増加でない値の列でも、最大値が下がらず最大の値を保つことを確認します。
    func testKeepsMaximumForNonMonotonicValues() {
        var tracker = RecordingSessionActivityMaximumTracker()
        for value in [30.0, 80.0, 50.0, 79.9] {
            tracker.record([RecordingSessionActivityTestSupport.sample(speed, value: value)])
        }
        XCTAssertEqual(tracker.maximums.vehicleSpeed, .value(80))
    }

    /// 責務: 項目ごとに独立して最大値を持ち、観測の無い項目は未取得のままであることを確認します。
    func testTracksEachMetricIndependently() {
        var tracker = RecordingSessionActivityMaximumTracker()
        tracker.record([
            RecordingSessionActivityTestSupport.sample(speed, value: 40),
            RecordingSessionActivityTestSupport.sample(rpm, value: 3000)
        ])
        tracker.record([RecordingSessionActivityTestSupport.sample(rpm, value: 2500)])
        XCTAssertEqual(tracker.maximums.vehicleSpeed, .value(40))
        XCTAssertEqual(tracker.maximums.engineSpeed, .value(3000))
        XCTAssertEqual(tracker.maximums.throttlePosition, .unavailable)
    }

    /// 責務: 空の観測一覧や対象外のPIDで最大値が変わらないことを確認します。
    func testIgnoresEmptyAndUnrelatedSamples() {
        var tracker = RecordingSessionActivityMaximumTracker()
        tracker.record([RecordingSessionActivityTestSupport.sample(speed, value: 10)])
        tracker.record([])
        tracker.record([RecordingSessionActivityTestSupport.sample(OBDPIDRequest(service: 0x01, pid: 0x05), value: 999)])
        XCTAssertEqual(tracker.maximums.vehicleSpeed, .value(10))
        XCTAssertEqual(tracker.maximums.engineSpeed, .unavailable)
    }

    /// 責務: 非有限値(NaN・無限大)を欠損として無視し、最大値を汚さないことを確認します。
    func testIgnoresNonFiniteValues() {
        var tracker = RecordingSessionActivityMaximumTracker()
        tracker.record([RecordingSessionActivityTestSupport.sample(throttle, value: .nan)])
        XCTAssertEqual(tracker.maximums.throttlePosition, .unavailable)
        tracker.record([RecordingSessionActivityTestSupport.sample(throttle, value: 20)])
        tracker.record([RecordingSessionActivityTestSupport.sample(throttle, value: .infinity)])
        XCTAssertEqual(tracker.maximums.throttlePosition, .value(20))
    }

    /// 責務: 0と負の値も最初の観測として最大値になることを確認します(0を未取得と混同しない)。
    func testZeroAndNegativeAreValidFirstValues() {
        var tracker = RecordingSessionActivityMaximumTracker()
        tracker.record([RecordingSessionActivityTestSupport.sample(speed, value: 0)])
        XCTAssertEqual(tracker.maximums.vehicleSpeed, .value(0))
        tracker.record([RecordingSessionActivityTestSupport.sample(rpm, value: -5)])
        XCTAssertEqual(tracker.maximums.engineSpeed, .value(-5))
    }

    /// 責務: セッション開始のリセットで全項目が未取得へ戻り、前のセッションの最大値を引き継がないことを確認します。
    func testResetClearsAllMaximums() {
        var tracker = RecordingSessionActivityMaximumTracker()
        tracker.record([
            RecordingSessionActivityTestSupport.sample(speed, value: 120),
            RecordingSessionActivityTestSupport.sample(rpm, value: 6000),
            RecordingSessionActivityTestSupport.sample(throttle, value: 90)
        ])
        tracker.reset()
        XCTAssertEqual(tracker.maximums, RecordingSessionActivityMaximumTracker().maximums)
        tracker.record([RecordingSessionActivityTestSupport.sample(speed, value: 5)])
        XCTAssertEqual(tracker.maximums.vehicleSpeed, .value(5))
    }
}
