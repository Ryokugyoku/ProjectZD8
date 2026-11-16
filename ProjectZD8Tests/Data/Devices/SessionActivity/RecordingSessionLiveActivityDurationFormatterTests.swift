import XCTest
@testable import ProjectZD8

/// `RecordingSessionLiveActivityDurationFormatter` の整形と境界を確認します。
final class RecordingSessionLiveActivityDurationFormatterTests: XCTestCase {
    private func format(_ seconds: TimeInterval) -> String {
        RecordingSessionLiveActivityDurationFormatter.string(seconds: seconds)
    }

    /// 責務: 1時間未満は `m:ss` になることを確認します(0・59・60・3599秒)。
    func testUnderOneHourUsesMinutesAndSeconds() {
        XCTAssertEqual(format(0), "0:00")
        XCTAssertEqual(format(59), "0:59")
        XCTAssertEqual(format(60), "1:00")
        XCTAssertEqual(format(3599), "59:59")
    }

    /// 責務: 1時間以上は `h:mm:ss` になることを確認します(3600秒ちょうど含む)。
    func testOneHourOrMoreUsesHours() {
        XCTAssertEqual(format(3600), "1:00:00")
        XCTAssertEqual(format(3661), "1:01:01")
        XCTAssertEqual(format(36_000), "10:00:00")
    }

    /// 責務: 小数秒は切り捨てられ、境界を跨がないことを確認します。
    func testFractionalSecondsAreTruncated() {
        XCTAssertEqual(format(59.9), "0:59")
        XCTAssertEqual(format(3599.99), "59:59")
        XCTAssertEqual(format(0.4), "0:00")
    }

    /// 責務: 負の値は0秒として整形することを確認します。
    func testNegativeIsZero() {
        XCTAssertEqual(format(-1), "0:00")
        XCTAssertEqual(format(-3600), "0:00")
    }
}
